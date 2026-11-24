import ApplicationServices
import Foundation

/// Window work, run on one serial queue: Accessibility calls block on the
/// target app, so they never run on the main thread, and two moves never
/// interleave.
final class WindowActions: @unchecked Sendable {
    let windows: WindowService
    let screens: ScreenService
    private let queue = DispatchQueue(label: "com.kellyredding.Trellis.windows", qos: .userInitiated)

    init(windows: WindowService, screens: ScreenService) {
        self.windows = windows
        self.screens = screens
    }

    func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    func perform(_ target: BindingTarget, config: TrellisConfig) -> Result<WindowInfo, RequestError> {
        windows.resolve(.focused).flatMap { window in
            PlacementPlanner.frame(for: target, window: window.info, screens: screens.screens, config: config)
                .flatMap { windows.setFrame(window, $0) }
        }
    }

    func place(_ request: PlaceRequest, config: TrellisConfig?) -> Result<WindowInfo, RequestError> {
        windows.resolve(request.target).flatMap { window in
            PlacementPlanner.frame(for: request, window: window.info, screens: screens.screens, config: config)
                .flatMap { windows.setFrame(window, $0) }
        }
    }

    func move(_ target: WindowTarget, _ direction: Direction) -> Result<WindowInfo, RequestError> {
        windows.resolve(target).flatMap { window in
            PlacementPlanner.move(window.info, direction, screens: screens.screens)
                .flatMap { windows.setFrame(window, $0) }
        }
    }

    func list(_ filter: WindowFilter) -> Result<[WindowInfo], RequestError> {
        TargetMatcher.filter(windows.allWindows().map(\.info), filter)
    }
}

/// Answers every socket event in docs/contract.md.
final class RequestHandler: @unchecked Sendable {
    private let model: AppModel
    private let actions: WindowActions

    init(model: AppModel, actions: WindowActions) {
        self.model = model
        self.actions = actions
    }

    func handle(_ line: Data) async -> Data {
        switch TrellisRequest.parse(line) {
        case .failure(let error):
            return Reply.failure(error)
        case .success(let request):
            return await handle(request)
        }
    }

    private func handle(_ request: TrellisRequest) async -> Data {
        switch request {
        case .status:
            return Reply.ok(await MainActor.run { model.statusData() })

        case .screens:
            return Reply.ok(ScreensData(screens: actions.screens.screens))

        case .configReload:
            return Reply.ok(await model.configStore.reload())

        case .windows(let filter):
            guard AXIsProcessTrusted() else { return Reply.failure(.notPermitted) }
            return reply(await actions.run { self.actions.list(filter) }) { WindowsData(windows: $0) }

        case .place(let place):
            guard AXIsProcessTrusted() else { return Reply.failure(.notPermitted) }
            let config = await MainActor.run { model.configStore.config }
            return reply(await actions.run { self.actions.place(place, config: config) }) { WindowData(window: $0) }

        case .screenMove(let target, let direction):
            guard AXIsProcessTrusted() else { return Reply.failure(.notPermitted) }
            return reply(await actions.run { self.actions.move(target, direction) }) { WindowData(window: $0) }

        case .chord(let keys):
            return await chord(keys)
        }
    }

    private func chord(_ keys: String) async -> Data {
        guard let config = await MainActor.run(body: { model.configStore.config }) else {
            return Reply.failure(.unavailable)
        }
        guard let tokens = KeyToken.chord(keys) else {
            return Reply.failure(.badRequest("\"\(keys)\" is not a chord"))
        }
        let canonical = KeyToken.chordDescription(tokens)
        guard let binding = ChordResolver.resolve(tokens, bindings: config.resolverBindings) else {
            return Reply.ok(ChordData(keys: canonical, target: nil, ran: false))
        }
        guard AXIsProcessTrusted() else { return Reply.failure(.notPermitted) }
        let result = await actions.run { self.actions.perform(binding.target, config: config) }
        return reply(result) { _ in ChordData(keys: canonical, target: binding.target, ran: true) }
    }

    private func reply<T, D: Encodable>(_ result: Result<T, RequestError>, _ wrap: (T) -> D) -> Data {
        switch result {
        case .success(let value): return Reply.ok(wrap(value))
        case .failure(let error): return Reply.failure(error)
        }
    }
}
