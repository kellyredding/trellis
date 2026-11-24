import Foundation

struct ResolverBinding: Equatable {
    let chord: [KeyToken]
    let target: BindingTarget
}

/// Accumulates the keys typed after the leader and decides when they name a
/// binding. Runs at once when the buffer matches a binding nothing longer
/// extends, rejects at once when no binding begins with it, and otherwise
/// waits; every key restarts the wait.
struct ChordResolver {
    enum Outcome: Equatable {
        case idle
        case waiting(buffer: [KeyToken], deadline: TimeInterval)
        case run(ResolverBinding)
        case unrecognized([KeyToken])
    }

    let bindings: [ResolverBinding]
    let wait: TimeInterval
    private let clock: () -> TimeInterval

    private(set) var buffer: [KeyToken] = []
    private(set) var deadline: TimeInterval?

    init(bindings: [ResolverBinding], wait: TimeInterval, clock: @escaping () -> TimeInterval) {
        self.bindings = bindings
        self.wait = wait
        self.clock = clock
    }

    mutating func feed(_ token: KeyToken) -> Outcome {
        buffer.append(token)
        let exact = bindings.first { $0.chord == buffer }
        let extendable = bindings.contains {
            $0.chord.count > buffer.count && Array($0.chord.prefix(buffer.count)) == buffer
        }
        if let exact, !extendable { return finish(.run(exact)) }
        if exact == nil, !extendable { return finish(.unrecognized(buffer)) }
        let due = clock() + wait
        deadline = due
        return .waiting(buffer: buffer, deadline: due)
    }

    /// Called when the wait timer fires; a call before the deadline changes
    /// nothing.
    mutating func expire() -> Outcome {
        guard let deadline, !buffer.isEmpty else { return .idle }
        guard clock() >= deadline else { return .waiting(buffer: buffer, deadline: deadline) }
        if let exact = bindings.first(where: { $0.chord == buffer }) {
            return finish(.run(exact))
        }
        return finish(.unrecognized(buffer))
    }

    mutating func clear() {
        buffer = []
        deadline = nil
    }

    private mutating func finish(_ outcome: Outcome) -> Outcome {
        clear()
        return outcome
    }

    /// A whole chord resolved as if typed after the leader and then left to
    /// expire. Anything that runs or is rejected before the last key is
    /// unbound.
    static func resolve(_ chord: [KeyToken], bindings: [ResolverBinding]) -> ResolverBinding? {
        var now: TimeInterval = 0
        var resolver = ChordResolver(bindings: bindings, wait: 1, clock: { now })
        for (index, token) in chord.enumerated() {
            let isLast = index == chord.count - 1
            switch resolver.feed(token) {
            case .run(let binding): return isLast ? binding : nil
            case .unrecognized, .idle: return nil
            case .waiting: continue
            }
        }
        now = 2
        if case .run(let binding) = resolver.expire() { return binding }
        return nil
    }
}
