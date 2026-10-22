import Foundation

struct Ticket: Identifiable, Equatable {
    let key: String
    let summary: String
    let type: String
    let isSubtask: Bool
    let status: TicketStatus
    let assignee: Person?
    let priority: String?

    var id: String { key }

    var project: String {
        Self.project(of: key)
    }

    static func project(of key: String) -> String {
        String(key.split(separator: "-").first ?? "")
    }

    func isAssigned(to email: String) -> Bool {
        assignee?.isSomeone(withEmail: email) ?? false
    }
}

struct Person: Decodable, Equatable {
    let accountID: String
    let displayName: String
    /// Nil when the person hides their email in their Atlassian profile.
    let email: String?

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case displayName
        case email = "emailAddress"
    }

    func isSomeone(withEmail address: String) -> Bool {
        email?.caseInsensitiveCompare(address) == .orderedSame
    }
}

struct TicketStatus: Hashable {
    let name: String
    let category: Category

    /// Jira files every workflow status under one of these, whatever the project calls it.
    enum Category: String, CaseIterable {
        case toDo = "new"
        case inProgress = "indeterminate"
        case done = "done"

        init(jiraKey: String) {
            self = Category(rawValue: jiraKey) ?? .toDo
        }

        var emoji: String {
            switch self {
            case .toDo: return "⚪"
            case .inProgress: return "🔵"
            case .done: return "🟢"
            }
        }

        var imageName: String {
            switch self {
            case .toDo: return "status-todo"
            case .inProgress: return "status-progress"
            case .done: return "status-success"
            }
        }
    }
}

extension Ticket: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key, fields
    }

    private struct Fields: Decodable {
        let summary: String
        let issuetype: IssueType
        let status: Status
        let assignee: Person?
        let priority: Priority?
    }

    private struct IssueType: Decodable {
        let name: String
        let subtask: Bool
    }

    private struct Status: Decodable {
        let name: String
        let statusCategory: StatusCategory
    }

    private struct StatusCategory: Decodable {
        let key: String
    }

    private struct Priority: Decodable {
        let name: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let fields = try container.decode(Fields.self, forKey: .fields)
        summary = fields.summary
        type = fields.issuetype.name
        isSubtask = fields.issuetype.subtask
        status = TicketStatus(name: fields.status.name,
                              category: TicketStatus.Category(jiraKey: fields.status.statusCategory.key))
        assignee = fields.assignee
        priority = fields.priority?.name
    }
}
