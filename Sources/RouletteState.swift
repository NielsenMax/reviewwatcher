import Foundation

/// The roulette's saved table: what the pool searches, who sits out, who each GitLab user is in Jira, and
/// every assignment the wheel made. The keys keep the Spanish names of the Node version's estado.json, so
/// that file reads as is.
struct RouletteState: Codable {
    var poolJQL: String
    var absentees: [String]
    var jiraUsers: [String: JiraUser]
    var assignments: [Assignment]

    static let defaultPoolJQL =
        #"assignee IS EMPTY AND statusCategory = "To Do" ORDER BY priority DESC, created ASC"#

    private enum CodingKeys: String, CodingKey {
        case poolJQL = "jql"
        case absentees = "ausentes"
        case jiraUsers
        case assignments = "planilla"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        poolJQL = try container.decodeIfPresent(String.self, forKey: .poolJQL) ?? Self.defaultPoolJQL
        absentees = try container.decodeIfPresent([String].self, forKey: .absentees) ?? []
        jiraUsers = try container.decodeIfPresent([String: JiraUser].self, forKey: .jiraUsers) ?? [:]
        assignments = try container.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
    }

    private init() {
        poolJQL = Self.defaultPoolJQL
        absentees = []
        jiraUsers = [:]
        assignments = []
    }

    static func load() throws -> RouletteState {
        guard FileManager.default.fileExists(atPath: Paths.rouletteStateFile.path) else { return RouletteState() }
        return try JSONDecoder().decode(RouletteState.self, from: Data(contentsOf: Paths.rouletteStateFile))
    }

    func save() throws {
        let directory = Paths.rouletteStateFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Paths.rouletteStateFile, options: .atomic)
    }
}

struct JiraUser: Codable, Equatable {
    let accountID: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case displayName
    }
}

/// One spin that ended with the ticket assigned in Jira.
struct Assignment: Codable, Identifiable, Equatable {
    let key: String
    let summary: String
    let username: String
    let name: String
    /// Milliseconds since 1970, as the Node version wrote them.
    let at: Double

    var id: String { "\(key)@\(at)" }

    var date: Date {
        Date(timeIntervalSince1970: at / 1000)
    }
}
