import Foundation

/// Runs a subprocess without parking a thread on it: both pipes drain through
/// `readabilityHandler`, exit arrives through `terminationHandler`, and a hard
/// timeout bounds every run. Adapted from Conduit's runner; a blocking
/// `waitUntilExit` leaks a thread whenever a termination notification is lost
/// across sleep and wake.
final class ProcessRunner: @unchecked Sendable {
    private let defaultTimeout: TimeInterval

    init(defaultTimeout: TimeInterval = 10) {
        self.defaultTimeout = defaultTimeout
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Self.drive(
                executable: executable,
                arguments: arguments,
                timeout: timeout ?? defaultTimeout,
                completion: { continuation.resume(with: $0) }
            )
        }
    }

    private static func drive(
        executable: URL,
        arguments: [String],
        timeout limit: TimeInterval,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let binary = executable.lastPathComponent
        let coord = DispatchQueue(label: "trellis.processrunner.\(binary)")
        let state = RunState()
        let timer = DispatchSource.makeTimerSource(queue: coord)
        timer.schedule(deadline: .now() + limit)

        func finish(_ result: Result<Data, Error>) {
            if state.finished { return }
            state.finished = true
            timer.cancel()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            completion(result)
        }

        func completeWithStatus() {
            let status = process.terminationStatus
            if status == 0 {
                finish(.success(state.outBuf))
            } else {
                finish(.failure(ProcessRunError.exited(
                    binary: binary, status: status,
                    standardOutput: state.outBuf, standardError: state.errBuf
                )))
            }
        }

        func completeIfReady() {
            guard !state.finished, state.pending == 0 else { return }
            completeWithStatus()
        }

        // Both pipes at EOF but no termination callback: once the process has
        // exited, resolve from its status rather than waiting out the hard
        // timeout. A child that closed its pipes and runs on meets the timeout.
        func armEofGrace() {
            guard !state.finished, state.outDone, state.errDone else { return }
            coord.asyncAfter(deadline: .now() + 2.0) {
                guard !state.finished else { return }
                if process.isRunning {
                    armEofGrace()
                } else {
                    completeWithStatus()
                }
            }
        }

        func drain(_ pipe: Pipe, isStandardOutput: Bool) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil }
                coord.async {
                    guard !state.finished else { return }
                    if chunk.isEmpty {
                        if isStandardOutput {
                            guard !state.outDone else { return }
                            state.outDone = true
                        } else {
                            guard !state.errDone else { return }
                            state.errDone = true
                        }
                        state.pending -= 1
                        completeIfReady()
                        armEofGrace()
                    } else if isStandardOutput {
                        state.outBuf.append(chunk)
                    } else {
                        state.errBuf.append(chunk)
                    }
                }
            }
        }

        drain(outPipe, isStandardOutput: true)
        drain(errPipe, isStandardOutput: false)

        process.terminationHandler = { _ in
            coord.async {
                guard !state.finished else { return }
                state.pending -= 1
                completeIfReady()
            }
        }

        timer.setEventHandler {
            guard !state.finished else { return }
            if process.isRunning { process.terminate() }
            let pid = process.processIdentifier
            coord.asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
            finish(.failure(ProcessRunError.timedOut(binary: binary, seconds: limit)))
        }

        do {
            try process.run()
        } catch {
            timer.cancel()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            completion(.failure(ProcessRunError.launchFailed(binary: binary, underlying: error)))
            return
        }

        coord.async {
            guard !state.finished else { return }
            timer.activate()
        }
    }
}

private final class RunState {
    var outBuf = Data()
    var errBuf = Data()
    var pending = 3
    var outDone = false
    var errDone = false
    var finished = false
}

enum ProcessRunError: Error, LocalizedError {
    case launchFailed(binary: String, underlying: Error)
    case exited(binary: String, status: Int32, standardOutput: Data, standardError: Data)
    case timedOut(binary: String, seconds: TimeInterval)

    /// The CLI reports failures on stderr; fall back to stdout, then the
    /// status, so a message is never empty.
    var errorDescription: String? {
        switch self {
        case .launchFailed(let binary, let underlying):
            return "\(binary) failed to launch: \(underlying.localizedDescription)"
        case .exited(let binary, let status, let out, let err):
            for data in [err, out] {
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
            return "\(binary) exited with status \(status)"
        case .timedOut(let binary, let seconds):
            return "\(binary) timed out after \(Int(seconds))s"
        }
    }
}
