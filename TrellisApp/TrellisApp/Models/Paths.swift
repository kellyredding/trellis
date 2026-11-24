import Foundation

/// Every path Trellis uses, each overridable from the environment so checks
/// run against temporary directories.
///
/// MIRROR: tools/trellis/src/trellis/paths.cr (see docs/contract.md, "Paths")
struct TrellisPaths: Equatable {
    let root: URL
    let configFile: URL
    let runtimeDir: URL
    let socket: URL
    let binary: URL

    var lockFile: URL { URL(fileURLWithPath: socket.path + ".lock") }
    var logsDir: URL { runtimeDir.appendingPathComponent("logs") }

    /// Kelly's config is a symlink into his dotfiles; hand edits land on the
    /// target, so that is the file worth watching and showing.
    var resolvedConfigFile: URL { configFile.resolvingSymlinksInPath() }

    var configIsSymlink: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: configFile.path)) != nil
    }

    init(environment: [String: String], home: URL) {
        func override(_ name: String) -> URL? {
            guard let value = environment[name], !value.isEmpty else { return nil }
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        root = override("TRELLIS_ROOT") ?? home.appendingPathComponent(".trellis")
        configFile = override("TRELLIS_CONFIG") ?? root.appendingPathComponent("config.json")
        runtimeDir = override("TRELLIS_RUNTIME_DIR") ?? root.appendingPathComponent("runtime")
        socket = override("TRELLIS_SOCKET") ?? runtimeDir.appendingPathComponent("trellis.sock")
        binary = override("TRELLIS_BINARY")
            ?? root.appendingPathComponent("bin").appendingPathComponent("trellis")
    }

    static var current: TrellisPaths {
        TrellisPaths(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}
