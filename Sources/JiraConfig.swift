import Foundation

/// The Epic tab's side of config.json. `site` and `email` stay empty until install.sh finds an acli login.
struct JiraConfig: Equatable {
    var site = ""
    var email = ""
    var epics: [String] = []
    var notifyOnNewTicket = true
    var notifyOnStatusChange = true
    var notifyOnAssigneeChange = true
    var notifyOnComment = true
    var showsDoneTickets = false

    var isSetUp: Bool {
        !site.isEmpty && !email.isEmpty
    }

    var emailDomain: String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: at)...]
        return domain.isEmpty ? nil : String(domain)
    }

    func browseURL(for key: String) -> URL? {
        URL(string: "https://\(site)/browse/\(key)")
    }
}

extension JiraConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case site, email, epics
        case notifyOnNewTicket, notifyOnStatusChange, notifyOnAssigneeChange, notifyOnComment
        case showDoneTickets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = JiraConfig()
        site = try container.decodeIfPresent(String.self, forKey: .site) ?? defaults.site
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? defaults.email
        epics = try container.decodeIfPresent([String].self, forKey: .epics) ?? defaults.epics
        notifyOnNewTicket = try container.decodeIfPresent(Bool.self, forKey: .notifyOnNewTicket) ?? defaults.notifyOnNewTicket
        notifyOnStatusChange = try container.decodeIfPresent(Bool.self, forKey: .notifyOnStatusChange) ?? defaults.notifyOnStatusChange
        notifyOnAssigneeChange = try container.decodeIfPresent(Bool.self, forKey: .notifyOnAssigneeChange) ?? defaults.notifyOnAssigneeChange
        notifyOnComment = try container.decodeIfPresent(Bool.self, forKey: .notifyOnComment) ?? defaults.notifyOnComment
        showsDoneTickets = try container.decodeIfPresent(Bool.self, forKey: .showDoneTickets) ?? defaults.showsDoneTickets
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(site, forKey: .site)
        try container.encode(email, forKey: .email)
        try container.encode(epics, forKey: .epics)
        try container.encode(notifyOnNewTicket, forKey: .notifyOnNewTicket)
        try container.encode(notifyOnStatusChange, forKey: .notifyOnStatusChange)
        try container.encode(notifyOnAssigneeChange, forKey: .notifyOnAssigneeChange)
        try container.encode(notifyOnComment, forKey: .notifyOnComment)
        try container.encode(showsDoneTickets, forKey: .showDoneTickets)
    }
}
