import Foundation
import Network

/// The CLI's socket: one JSON line in, one JSON line out, then the app closes
/// the connection. Adapted from Assist Ant's `SocketListener` (NWListener on a
/// Unix endpoint, a flock single-instance lock, stale socket removal).
final class SocketServer: @unchecked Sendable {
    enum StartResult: Equatable {
        case listening
        case anotherInstance
        case failed(String)
    }

    private let socketPath: String
    private let lockPath: String
    private let queue = DispatchQueue(label: "com.kellyredding.Trellis.socket")
    private var listener: NWListener?
    private var lockFileDescriptor: Int32 = -1
    private let stateLock = NSLock()
    private var stopped = false
    private var restartAttempts = 0
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var idleTimers: [ObjectIdentifier: DispatchWorkItem] = [:]
    private static let maxRequestBytes = 1024 * 1024
    private static let maxRestartAttempts = 5
    private static let idleTimeout: TimeInterval = 10

    /// Turns one request line into one reply line (no trailing newline).
    var handler: ((Data) async -> Data)?
    /// Called on the socket queue once the listener has failed for good.
    var onProblem: ((String) -> Void)?

    init(socketPath: String, lockPath: String) {
        self.socketPath = socketPath
        self.lockPath = lockPath
    }

    deinit { stop() }

    func start() -> StartResult {
        guard acquireLock() else { return .anotherInstance }
        // Holding the lock means any socket file left behind is stale.
        try? FileManager.default.removeItem(atPath: socketPath)

        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        do {
            listener = try NWListener(using: parameters)
        } catch {
            releaseLock()
            return .failed("could not listen on \(socketPath): \(error.localizedDescription)")
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.restartAttempts = 0
                chmod(self.socketPath, 0o600)
                Log.info("listening on \(self.socketPath)")
            case .failed(let error):
                Log.error("socket listener failed: \(error.localizedDescription)")
                self.restartAfterFailure("the socket listener failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.start(queue: queue)
        return .listening
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        stopped = true
        listener?.cancel()
        listener = nil
        // Without the lock the socket file belongs to the instance holding it.
        guard lockFileDescriptor >= 0 else { return }
        try? FileManager.default.removeItem(atPath: socketPath)
        releaseLock()
    }

    // MARK: - Lock

    private func acquireLock() -> Bool {
        if lockFileDescriptor >= 0 { return true }
        let directory = (lockPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        lockFileDescriptor = descriptor
        return true
    }

    /// Never deletes the lock file: a launch that opened it before the unlink
    /// would lock the orphaned inode while the next launch locks a new one.
    private func releaseLock() {
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }

    private func restartAfterFailure(_ problem: String) {
        restartAttempts += 1
        guard restartAttempts <= Self.maxRestartAttempts else {
            Log.error("\(problem); giving up after \(Self.maxRestartAttempts) restarts")
            onProblem?(problem)
            return
        }
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            defer { self.stateLock.unlock() }
            guard !self.stopped else { return }
            self.listener?.cancel()
            self.listener = nil
            switch self.start() {
            case .listening:
                break
            case .anotherInstance:
                self.onProblem?("another Trellis took the socket lock")
            case .failed(let message):
                Log.error(message)
                self.restartAfterFailure(message)
            }
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        buffers[key] = Data()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .cancelled:
                self?.buffers[key] = nil
                self?.disarmIdleTimeout(key)
            case .failed:
                self?.buffers[key] = nil
                self?.disarmIdleTimeout(key)
                connection?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        armIdleTimeout(connection)
        receive(on: connection)
    }

    /// A client that connects and never finishes its line is cut off.
    private func armIdleTimeout(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        idleTimers[key]?.cancel()
        let timeout = DispatchWorkItem { connection.cancel() }
        idleTimers[key] = timeout
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: timeout)
    }

    private func disarmIdleTimeout(_ key: ObjectIdentifier) {
        idleTimers.removeValue(forKey: key)?.cancel()
    }

    private func receive(on connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.disarmIdleTimeout(key)
            var buffer = self.buffers[key] ?? Data()
            if let data { buffer.append(data) }

            if let newline = buffer.firstIndex(of: 0x0A) {
                self.buffers[key] = Data()
                self.respond(to: Data(buffer[buffer.startIndex..<newline]), on: connection)
            } else if isComplete || error != nil {
                self.buffers[key] = Data()
                if buffer.isEmpty {
                    connection.cancel()
                } else {
                    self.respond(to: buffer, on: connection)
                }
            } else if buffer.count > Self.maxRequestBytes {
                self.buffers[key] = Data()
                self.send(Reply.failure(.badRequest("request too large")), on: connection)
            } else {
                self.buffers[key] = buffer
                self.armIdleTimeout(connection)
                self.receive(on: connection)
            }
        }
    }

    private func respond(to line: Data, on connection: NWConnection) {
        guard let handler else {
            send(Reply.failure(RequestError(code: .unavailable, message: "Trellis is starting")), on: connection)
            return
        }
        Task {
            let reply = await handler(line)
            self.send(reply, on: connection)
        }
    }

    private func send(_ reply: Data, on connection: NWConnection) {
        var framed = reply
        framed.append(0x0A)
        connection.send(content: framed, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
