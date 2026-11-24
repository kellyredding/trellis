import Foundation

/// The loaded config. Loads at launch, on `config.reload`, and when the
/// resolved config file changes on disk; an invalid config keeps the last
/// good one live and exposes the error.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: TrellisConfig?
    @Published private(set) var error: String?
    @Published private(set) var loadedAt: Date?

    let paths: TrellisPaths
    private let cli: CLIRunner
    private var watcher: FileWatcher?
    private var watchedDirectories: [String] = []
    private var current: Task<ReloadData, Never>?

    init(paths: TrellisPaths, cli: CLIRunner) {
        self.paths = paths
        self.cli = cli
    }

    var isLoaded: Bool { config != nil }

    func start() {
        Task { await reload() }
    }

    /// Reloads run one after another, so a burst (the CLI's `config.reload`
    /// and the file event for the same write) never races.
    @discardableResult
    func reload() async -> ReloadData {
        let previous = current
        let task = Task { @MainActor () -> ReloadData in
            _ = await previous?.value
            return await self.load()
        }
        current = task
        return await task.value
    }

    private func load() async -> ReloadData {
        defer { rewatch() }
        do {
            let loaded = try await cli.exportConfig()
            if loaded != config { config = loaded }
            error = nil
            loadedAt = Date()
            Log.info("config loaded from \(loaded.source) (\(loaded.bindings.count) bindings)")
            return ReloadData(loaded: true, error: nil)
        } catch {
            let message = error.localizedDescription
            self.error = message
            Log.error("config reload failed: \(message)")
            return ReloadData(loaded: false, error: message)
        }
    }

    private func rewatch() {
        let candidates = [paths.configFile, paths.resolvedConfigFile]
            .map { $0.deletingLastPathComponent().path }
        var directories: [String] = []
        for directory in candidates where !directories.contains(directory) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
                directories.append(directory)
            }
        }
        guard directories != watchedDirectories else { return }
        watchedDirectories = directories
        watcher = FileWatcher(directories: directories) { [weak self] changed in
            MainActor.assumeIsolated { self?.filesChanged(changed) }
        }
    }

    /// FSEvents is recursive, so only the config file itself counts.
    private func filesChanged(_ changed: [String]) {
        let watched = Set([paths.configFile.path, paths.resolvedConfigFile.path].map(Self.canonical))
        guard changed.contains(where: { watched.contains(Self.canonical($0)) }) else { return }
        Task { await reload() }
    }

    /// FSEvents reports real paths (`/private/tmp`, link targets); the file
    /// itself may already be gone, so only its directory is resolved.
    private static func canonical(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let real = realpath(url.deletingLastPathComponent().path, nil) else { return url.path }
        defer { free(real) }
        return (String(cString: real) as NSString).appendingPathComponent(url.lastPathComponent)
    }
}
