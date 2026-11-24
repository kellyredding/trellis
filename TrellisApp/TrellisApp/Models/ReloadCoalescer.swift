import Foundation

/// Folds requests that arrive within `window` of each other into one run of
/// `perform`, whose outcome every one of them receives. A request joins the
/// run still waiting to start, or schedules one `window` later; runs never
/// overlap, and a run always starts after every request it answers.
actor ReloadCoalescer<Outcome: Sendable> {
    private let window: TimeInterval
    private let perform: @Sendable () async -> Outcome
    private var waiting: Task<Outcome, Never>?
    private var latest: Task<Outcome, Never>?

    init(window: TimeInterval, perform: @escaping @Sendable () async -> Outcome) {
        self.window = window
        self.perform = perform
    }

    func request() async -> Outcome {
        if let waiting { return await waiting.value }
        let previous = latest
        let task = Task { () -> Outcome in
            try? await Task.sleep(nanoseconds: UInt64(self.window * 1_000_000_000))
            _ = await previous?.value
            self.waiting = nil
            return await self.perform()
        }
        waiting = task
        latest = task
        return await task.value
    }
}
