import Foundation

struct JiraClient {
    /// launchd hands the agent a bare PATH, so acli is located explicitly.
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func locateAcli() throws -> String {
        let candidates = searchPaths.map { "\($0)/acli" }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw WatcherError.setup("acli not found in \(searchPaths.joined(separator: ", "))")
        }
        return found
    }

    func search(_ jql: String) throws -> [Ticket] {
        try decode([Ticket].self, from: runAcli(["jira", "workitem", "search", "--jql", jql, "--json", "--paginate"]))
    }

    func recentlyUpdated(in project: String, limit: Int) throws -> [Ticket] {
        let jql = "project = \(project) ORDER BY updated DESC"
        let arguments = ["jira", "workitem", "search", "--jql", jql, "--json", "--limit", String(limit)]
        return try decode([Ticket].self, from: runAcli(arguments))
    }

    /// Each `view` spends a second or more on acli start-up and the round trip, so they run side by side.
    func activities(of keys: [String]) throws -> [String: TicketActivity] {
        var results = [Result<TicketActivity, Error>](repeating: .failure(WatcherError.acli("not fetched")),
                                                       count: keys.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: keys.count) { index in
            let result = Result { try activity(of: keys[index]) }
            lock.lock()
            results[index] = result
            lock.unlock()
        }
        var activities: [String: TicketActivity] = [:]
        for (key, result) in zip(keys, results) {
            do {
                activities[key] = try result.get()
            } catch {
                throw WatcherError.acli("could not read \(key): \(error.localizedDescription)")
            }
        }
        return activities
    }

    func transition(_ key: String, to status: String) throws {
        try runChange(["jira", "workitem", "transition", "--key", key, "--status", status])
    }

    func assignToMe(_ key: String) throws {
        try runChange(["jira", "workitem", "assign", "--key", key, "--assignee", "@me"])
    }

    func unassign(_ key: String) throws {
        try runChange(["jira", "workitem", "assign", "--key", key, "--remove-assignee"])
    }

    private func activity(of key: String) throws -> TicketActivity {
        try decode(TicketActivity.self, from: runAcli(["jira", "workitem", "view", key, "--fields", "parent,comment", "--json"]))
    }

    /// acli exits 0 even when Jira refuses the change; only the per-item results tell.
    private func runChange(_ arguments: [String]) throws {
        let outcome = try decode(ChangeOutcome.self, from: runAcli(arguments + ["--yes", "--json"]))
        guard outcome.successCount == outcome.totalCount else {
            let refusal = outcome.results.first { $0.status == "FAILURE" }?.message
            throw WatcherError.acli(refusal ?? "\(outcome.successCount) of \(outcome.totalCount) changes applied")
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let excerpt = String(decoding: data.prefix(200), as: UTF8.self)
            throw WatcherError.acli("expected \(Value.self) as JSON, got \(excerpt): \(error)")
        }
    }

    private func runAcli(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try Self.locateAcli())
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
            let detail = [stderr, stdout]
                .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            throw WatcherError.acli(detail ?? "exit \(process.terminationStatus)")
        }
        return stdout
    }

    private struct ChangeOutcome: Decodable {
        let results: [ItemResult]
        let totalCount: Int
        let successCount: Int

        struct ItemResult: Decodable {
            let status: String
            let message: String?
        }
    }
}
