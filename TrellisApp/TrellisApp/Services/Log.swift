import Foundation
import os

/// Unified logging plus a plain file under the runtime logs directory, so an
/// agent can read what the app saw without `log show`.
enum Log {
    private static let logger = Logger(subsystem: "com.kellyredding.Trellis", category: "app")
    private static let queue = DispatchQueue(label: "com.kellyredding.Trellis.log")
    private static let maxBytes: UInt64 = 1_000_000
    private static let formatter = ISO8601DateFormatter()

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append("INFO  \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR \(message)")
    }

    private static func append(_ line: String) {
        let stamp = formatter.string(from: Date())
        queue.async {
            let directory = TrellisPaths.current.logsDir
            let file = directory.appendingPathComponent("trellis.log")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? UInt64,
               size > maxBytes {
                let previous = directory.appendingPathComponent("trellis.log.1")
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: file, to: previous)
            }
            guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file)
            }
        }
    }
}
