import Foundation

/// Runs the argocd CLI with the login `argocd login` stored. Commands run one at a time: Argo rotates the SSO
/// refresh token on every use, and two commands refreshing at once leave one of them, and the stored login,
/// holding a token already spent.
final class ArgoClient {
    /// launchd hands the agent a bare PATH, so argocd is located explicitly.
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    private static let expiredSessionHints = ["refresh token", "token is expired", "unauthenticated", "invalid session"]

    private let lock = NSLock()

    static func locateArgo() throws -> String {
        let candidates = searchPaths.map { "\($0)/argocd" }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw WatcherError.setup("argocd not found in \(searchPaths.joined(separator: ", "))")
        }
        return found
    }

    func applications() throws -> [ArgoApp] {
        try decode([ArgoApp].self, from: run(["app", "list", "-o", "json"]))
    }

    func application(named name: String) throws -> ArgoApp {
        try decode(ArgoApp.self, from: run(["app", "get", name, "-o", "json"]))
    }

    /// Returns once Argo has accepted the operation, before it runs.
    func sync(_ name: String) throws {
        _ = try run(["app", "sync", name, "--async"])
    }

    /// The host of the current context, as `argocd context` marks it with a star.
    func server() throws -> String {
        let listing = String(decoding: try run(["context"]), as: UTF8.self)
        for line in listing.split(separator: "\n") {
            let columns = line.split(whereSeparator: \.isWhitespace)
            if columns.first == "*", let server = columns.last {
                return String(server)
            }
        }
        throw WatcherError.argocd("no current context in: \(listing.prefix(200))")
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let excerpt = String(decoding: data.prefix(200), as: UTF8.self)
            throw WatcherError.argocd("expected \(Value.self) as JSON, got \(excerpt): \(error)")
        }
    }

    private func run(_ arguments: [String]) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try Self.locateArgo())
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPaths.joined(separator: ":") + ":/bin"
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = Self.message(in: stderr) ?? "exit \(process.terminationStatus)"
            if Self.expiredSessionHints.contains(where: detail.lowercased().contains) {
                throw WatcherError.argocd("session expired, run argocd login with --sso: \(detail)")
            }
            throw WatcherError.argocd(detail)
        }
        return stdout
    }

    /// argocd logs a failure as a JSON line whose `msg` holds the reason.
    private static func message(in stderr: Data) -> String? {
        let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let reasons = text.split(separator: "\n").compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(LogLine.self, from: data) else { return nil }
            return entry.msg
        }
        return reasons.isEmpty ? text : reasons.joined(separator: "; ")
    }

    private struct LogLine: Decodable {
        let msg: String
    }
}
