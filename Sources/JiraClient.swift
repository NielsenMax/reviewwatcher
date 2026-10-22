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

    /// Without a limit, every page of results is fetched. Without fields, acli returns type, key, assignee,
    /// priority, status and summary.
    func search(_ jql: String, fields: [String]? = nil, limit: Int? = nil) throws -> [Ticket] {
        let scope = limit.map { ["--limit", String($0)] } ?? ["--paginate"]
        let fieldList = fields.map { ["--fields", $0.joined(separator: ",")] } ?? []
        let arguments = ["jira", "workitem", "search", "--jql", jql, "--json"] + fieldList + scope
        return try decode([Ticket].self, from: runAcli(arguments))
    }

    /// acli prints a bare null, not an issue without a parent field, when the issue has no parent.
    func parent(of key: String) throws -> ParentLink? {
        try decode(ParentView?.self, from: runAcli(["jira", "workitem", "view", key, "--fields", "parent", "--json"]))?
            .fields.parent
    }

    func assign(_ key: String, toAccount accountID: String) throws {
        try runChange(["jira", "workitem", "assign", "--key", key, "--assignee", accountID])
    }

    /// Each `view` spends a second or more on acli start-up and the round trip, so they run side by side.
    func activities(of keys: [String]) throws -> [String: TicketActivity] {
        var activities: [String: TicketActivity] = [:]
        for (key, result) in zip(keys, concurrently(keys, activity(of:))) {
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
                .map { $0.replacingOccurrences(of: #"^✗ (Error: )?"#, with: "", options: .regularExpression) }
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

struct ParentLink: Decodable {
    let key: String
    let summary: String
    /// 1 for an epic, 0 for a story or task, -1 for a subtask.
    let hierarchyLevel: Int

    private enum CodingKeys: String, CodingKey {
        case key, fields
    }

    private struct Fields: Decodable {
        let summary: String?
        let issuetype: IssueType
    }

    private struct IssueType: Decodable {
        let hierarchyLevel: Int
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let fields = try container.decode(Fields.self, forKey: .fields)
        summary = fields.summary ?? ""
        hierarchyLevel = fields.issuetype.hierarchyLevel
    }
}

private struct ParentView: Decodable {
    let fields: Fields

    struct Fields: Decodable {
        let parent: ParentLink?
    }
}
