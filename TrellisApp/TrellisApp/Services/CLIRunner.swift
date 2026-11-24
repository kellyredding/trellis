import Foundation

enum CLIError: LocalizedError {
    case missing(String)
    case failed(String)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .missing(let path): return "the trellis CLI is not installed at \(path)"
        case .failed(let message): return message
        case .undecodable(let message): return "could not read the config export: \(message)"
        }
    }
}

/// Runs the trellis CLI at its installed path (or `TRELLIS_BINARY`). The app
/// never reads or writes the config itself; everything goes through here.
final class CLIRunner: @unchecked Sendable {
    let paths: TrellisPaths
    private let runner = ProcessRunner(defaultTimeout: 10)

    init(paths: TrellisPaths) {
        self.paths = paths
    }

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: paths.binary.path) }

    func exportConfig() async throws -> TrellisConfig {
        let data = try await run(["config", "export", "--json"])
        do {
            return try TrellisConfig.decode(data)
        } catch {
            throw CLIError.undecodable(String(describing: error))
        }
    }

    func setSetting(_ key: String, _ value: String) async throws {
        _ = try await run(["settings", "set", key, value])
    }

    func version() async -> String? {
        guard let data = try? await run(["version"], timeout: 5) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.split(separator: "\n").first.map(String.init)
    }

    private func run(_ arguments: [String], timeout: TimeInterval? = nil) async throws -> Data {
        guard isInstalled else { throw CLIError.missing(paths.binary.path) }
        do {
            return try await runner.run(executable: paths.binary, arguments: arguments, timeout: timeout)
        } catch {
            throw CLIError.failed(error.localizedDescription)
        }
    }
}
