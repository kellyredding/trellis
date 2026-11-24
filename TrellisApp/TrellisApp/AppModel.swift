import AppKit
import Combine

/// Owns the services and wires them together; the menu and settings window
/// observe it.
@MainActor
final class AppModel: ObservableObject {
    let paths: TrellisPaths
    let cli: CLIRunner
    let configStore: ConfigStore
    let accessibility = Accessibility()
    let layoutMode = LayoutMode()
    let screens = ScreenService()
    let hotkey = Hotkey()
    let windows: WindowService
    let actions: WindowActions
    let overlay: Overlay
    private var socket: SocketServer?
    private var handler: RequestHandler?
    private var subscriptions: Set<AnyCancellable> = []

    @Published private(set) var cliVersion: String?
    @Published private(set) var settingsError: String?
    @Published private(set) var socketProblem: String?
    @Published private(set) var lastActionError: String?
    @Published private(set) var isCapturingLeader = false

    init(paths: TrellisPaths = .current) {
        self.paths = paths
        cli = CLIRunner(paths: paths)
        configStore = ConfigStore(paths: paths, cli: cli)
        windows = WindowService(screens: screens)
        actions = WindowActions(windows: windows, screens: screens)
        overlay = Overlay(layoutMode: layoutMode, configStore: configStore, screens: screens)
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    var iconState: MenuIconState {
        .state(accessibilityTrusted: accessibility.isTrusted, layoutModeActive: layoutMode.isActive)
    }

    var leader: KeyToken {
        configStore.config?.settings.leaderToken ?? KeyToken(Settings.defaultLeader)!
    }

    /// False when another instance holds the socket lock; the caller quits.
    func start() -> Bool {
        try? FileManager.default.createDirectory(
            at: paths.runtimeDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.createDirectory(at: paths.logsDir, withIntermediateDirectories: true)

        let socket = SocketServer(socketPath: paths.socket.path, lockPath: paths.lockFile.path)
        let handler = RequestHandler(model: self, actions: actions)
        socket.handler = { await handler.handle($0) }
        socket.onProblem = { [weak self] message in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.socketProblem = message } }
        }
        switch socket.start() {
        case .anotherInstance:
            Log.error("another Trellis holds \(paths.lockFile.path); quitting")
            return false
        case .failed(let message):
            socketProblem = message
            Log.error(message)
        case .listening:
            break
        }
        self.socket = socket
        self.handler = handler

        for publisher in [
            configStore.objectWillChange.eraseToAnyPublisher(),
            accessibility.objectWillChange.eraseToAnyPublisher(),
            layoutMode.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }

        configStore.$config
            .sink { [weak self] config in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.configChanged(config) } }
            }
            .store(in: &subscriptions)
        accessibility.$isTrusted
            .removeDuplicates()
            .sink { [weak self] trusted in
                if !trusted { self?.layoutMode.exit(reason: "Accessibility permission lost") }
            }
            .store(in: &subscriptions)

        hotkey.onPress = { [weak self] in self?.leaderPressed() }
        hotkey.register(leader)
        layoutMode.onRun = { [weak self] binding in self?.run(binding) }
        layoutMode.start()

        screens.start { [weak self] in self?.overlay.refresh() }
        accessibility.start()
        configStore.start()
        Task { cliVersion = await cli.version() }
        return true
    }

    func stop() {
        layoutMode.exit(reason: "quit")
        hotkey.unregister()
        socket?.stop()
    }

    func enterLayoutMode() {
        layoutMode.enter(config: configStore.config, leader: leader)
        locateTargetScreen()
    }

    func reloadConfig() {
        Task {
            await configStore.reload()
            cliVersion = await cli.version()
        }
    }

    func saveSetting(_ key: String, _ value: String) {
        Task {
            do {
                try await cli.setSetting(key, value)
                settingsError = nil
            } catch {
                settingsError = error.localizedDescription
                Log.error("settings set \(key) failed: \(error.localizedDescription)")
            }
            await configStore.reload()
        }
    }

    /// While the settings window records a new leader, the current one must
    /// neither fire nor swallow the keystroke being recorded.
    func setCapturingLeader(_ capturing: Bool) {
        guard capturing != isCapturingLeader else { return }
        isCapturingLeader = capturing
        if capturing {
            layoutMode.exit(reason: "recording a leader")
            hotkey.suspend()
        } else {
            hotkey.resume()
        }
    }

    func statusData() -> StatusData {
        StatusData(
            version: version,
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            accessibility: accessibility.isTrusted,
            layoutMode: layoutMode.isActive,
            config: .init(
                path: paths.configFile.path,
                source: configStore.config?.source,
                loaded: configStore.isLoaded,
                error: configStore.error
            )
        )
    }

    private func leaderPressed() {
        let wasActive = layoutMode.isActive
        layoutMode.leaderPressed(config: configStore.config, leader: leader)
        if !wasActive, layoutMode.isActive { locateTargetScreen() }
    }

    private func configChanged(_ config: TrellisConfig?) {
        hotkey.register(leader)
        layoutMode.leaderChanged(to: leader)
        if config?.settings.label.screens == .target { locateTargetScreen() }
    }

    private func locateTargetScreen() {
        guard layoutMode.isActive, configStore.config?.settings.label.screens == .target else { return }
        Task {
            let index = await actions.run { self.windows.focusedWindow()?.info.screen }
            overlay.setTargetScreen(index)
        }
    }

    /// A chord typed in layout mode; the socket's `chord` event runs through
    /// `RequestHandler` and shows no confirmation.
    private func run(_ binding: ResolverBinding) {
        guard let config = configStore.config else { return }
        let target = binding.target
        let confirmation = overlay.beginConfirmation(ChordConfirmation(chord: binding.chord, target: target))
        Task {
            let result = await actions.run { self.actions.perform(target, config: config) }
            switch result {
            case .success(let window):
                lastActionError = nil
                Log.info("\(target) → \(window.app) \(window.frame)")
                overlay.finishConfirmation(confirmation, .succeeded)
            case .failure(let error):
                lastActionError = error.message
                Log.error("\(target) failed: \(error.message)")
                overlay.finishConfirmation(confirmation, .failed(error.message))
                NSSound.beep()
            }
        }
    }
}
