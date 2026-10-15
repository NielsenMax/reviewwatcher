import Foundation

/// Writes to its own file so the log survives however the agent was launched:
/// launchd redirects stderr, but LaunchServices discards it.
enum Log {
    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/reviewwatcher.log")

    private static let serial = DispatchQueue(label: "app.reviewwatcher.log")
    private static let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func write(_ message: String) {
        let line = Data("[\(timestamps.string(from: Date()))] \(message)\n".utf8)
        serial.sync {
            guard let handle = try? FileHandle(forWritingTo: file) else {
                try? line.write(to: file)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
