import Foundation

struct Player: Identifiable, Equatable {
    let username: String
    let name: String
    let teams: [String]
    let jira: JiraUser?
    var isActive: Bool
    /// Open tickets assigned to them under the configured load JQL.
    var openLoad: Int

    var id: String { username }

    var canPlay: Bool {
        isActive && jira != nil
    }
}

struct EpicRef: Equatable {
    let key: String
    let summary: String
}

/// The roulette's reads and writes: players from GitLab's team groups, the pool from Jira, and the record of
/// who got what. Blocking; callers run it off the main queue. `state` is only touched under `lock`.
final class RouletteService {
    private let gitlab: GitLabClient
    private let jira: JiraClient
    private let config: RouletteConfig
    /// Where company emails live, taken from the Jira login; nil leaves every player without a Jira user.
    private let emailDomain: String?
    private var state: RouletteState
    private let lock = NSLock()
    private var epicCache: [String: (epic: EpicRef?, fetchedAt: Date)] = [:]

    /// Owners of the teams group administer every subgroup; they are not members of the team they own.
    private static let ownerAccessLevel = 50
    private static let poolFields = ["key", "summary", "priority", "status", "issuetype", "labels"]
    private static let poolLimit = 100
    private static let epicLifetime: TimeInterval = 10 * 60
    private static let epicLevel = 1

    init(gitlab: GitLabClient, jira: JiraClient, config: RouletteConfig, emailDomain: String?) throws {
        self.gitlab = gitlab
        self.jira = jira
        self.config = config
        self.emailDomain = emailDomain
        self.state = try RouletteState.load()
    }

    var snapshot: RouletteState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func players() throws -> [Player] {
        let roster = try teamRoster()
        try mapJiraUsers(roster)
        let load = try openLoadByAccount()
        let current = snapshot
        let absentees = Set(current.absentees)
        return roster.map { member in
            let jiraUser = current.jiraUsers[member.username]
            return Player(username: member.username, name: member.name, teams: member.teams, jira: jiraUser,
                          isActive: !absentees.contains(member.username),
                          openLoad: jiraUser.map { load[$0.accountID] ?? 0 } ?? 0)
        }
    }

    func pool() throws -> (jql: String, tickets: [Ticket]) {
        let jql = snapshot.poolJQL
        return (jql, try pool(matching: jql))
    }

    /// Runs the search before saving it, so a JQL Jira rejects never replaces the one that works.
    func replacePoolJQL(with jql: String) throws -> [Ticket] {
        let trimmed = jql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WatcherError.setup("El JQL llegó vacío") }
        let tickets = try pool(matching: trimmed)
        try mutate { $0.poolJQL = trimmed }
        return tickets
    }

    func epics(of keys: [String]) throws -> [String: EpicRef?] {
        var epics: [String: EpicRef?] = [:]
        for (key, outcome) in zip(keys, concurrently(keys, epic(of:))) {
            epics[key] = try outcome.get()
        }
        return epics
    }

    func assign(_ key: String, to username: String) throws -> Assignment {
        try Self.validate(key)
        guard let jiraUser = snapshot.jiraUsers[username] else {
            throw WatcherError.setup("\(username) no tiene usuario de Jira mapeado")
        }
        guard let ticket = try jira.search("key = \(key)", limit: 1).first else {
            throw WatcherError.setup("\(key) no existe en Jira")
        }
        if let assignee = ticket.assignee {
            throw WatcherError.setup("\(key) ya está asignado a \(assignee.displayName) en Jira")
        }
        try jira.assign(key, toAccount: jiraUser.accountID)
        let assignment = Assignment(key: key, summary: ticket.summary, username: username,
                                    name: jiraUser.displayName, at: (Date().timeIntervalSince1970 * 1000).rounded())
        try mutate { $0.assignments.insert(assignment, at: 0) }
        return assignment
    }

    func unassign(_ key: String) throws {
        try Self.validate(key)
        try jira.unassign(key)
        try mutate { $0.assignments.removeAll { $0.key == key } }
    }

    func setActive(_ username: String, _ isActive: Bool) throws {
        try mutate { state in
            var absentees = Set(state.absentees)
            if isActive {
                absentees.remove(username)
            } else {
                absentees.insert(username)
            }
            state.absentees = absentees.sorted()
        }
    }

    private func pool(matching jql: String) throws -> [Ticket] {
        try jira.search(jql, fields: Self.poolFields, limit: Self.poolLimit)
    }

    private func teamRoster() throws -> [RosterMember] {
        guard !config.teamsGroup.isEmpty else {
            throw WatcherError.setup("Falta roulette.teamsGroup en \(Paths.configFile.path)")
        }
        let teams = try gitlab.subgroups(of: config.teamsGroup)
        let memberships = concurrently(teams) { try gitlab.members(ofGroup: $0.id) }
        var roster: [String: RosterMember] = [:]
        var order: [String] = []
        for (team, outcome) in zip(teams, memberships) {
            for member in try outcome.get() where member.accessLevel < Self.ownerAccessLevel && member.state == "active" {
                if roster[member.username] == nil {
                    roster[member.username] = RosterMember(username: member.username, name: member.name, teams: [])
                    order.append(member.username)
                }
                roster[member.username]?.teams.append(team.path)
            }
        }
        return order.compactMap { roster[$0] }
    }

    private func mapJiraUsers(_ roster: [RosterMember]) throws {
        let known = snapshot.jiraUsers
        let unmapped = roster.filter { known[$0.username] == nil }
        var found: [String: JiraUser] = [:]
        for (member, outcome) in zip(unmapped, concurrently(unmapped, jiraUser(for:))) {
            found[member.username] = try outcome.get()
        }
        guard !found.isEmpty else { return }
        try mutate { $0.jiraUsers.merge(found) { _, new in new } }
    }

    /// acli has no user search; JQL resolves an email to an account, but only through an issue the person was
    /// assigned. An unknown email finds no issues rather than failing.
    private func jiraUser(for member: RosterMember) throws -> JiraUser? {
        guard let emailDomain, let email = Self.companyEmail(for: member.name, at: emailDomain) else { return nil }
        let latest = try jira.search(#"assignee = "\#(email)" ORDER BY updated DESC"#, limit: 1).first
        return latest?.assignee.map { JiraUser(accountID: $0.accountID, displayName: $0.displayName) }
    }

    private func openLoadByAccount() throws -> [String: Int] {
        var load: [String: Int] = [:]
        guard !config.loadJQL.isEmpty else { return load }
        for ticket in try jira.search(config.loadJQL) {
            if let accountID = ticket.assignee?.accountID {
                load[accountID, default: 0] += 1
            }
        }
        return load
    }

    /// A subtask's parent is a story, so its epic is one level further up.
    private func epic(of key: String) throws -> EpicRef? {
        if let cached = cachedEpic(of: key) { return cached.epic }
        let parent = try jira.parent(of: key)
        let epic: EpicRef?
        if let parent, parent.hierarchyLevel == Self.epicLevel {
            epic = EpicRef(key: parent.key, summary: parent.summary)
        } else if let parent, parent.hierarchyLevel < Self.epicLevel {
            epic = try self.epic(of: parent.key)
        } else {
            epic = nil
        }
        lock.lock()
        epicCache[key] = (epic, Date())
        lock.unlock()
        return epic
    }

    private func cachedEpic(of key: String) -> (epic: EpicRef?, fetchedAt: Date)? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = epicCache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.epicLifetime else { return nil }
        return cached
    }

    private func mutate(_ change: (inout RouletteState) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = state
        change(&next)
        try next.save()
        state = next
    }

    static func companyEmail(for name: String, at domain: String) -> String? {
        let parts = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.filter { ("a"..."z").contains($0) } }
            .filter { !$0.isEmpty }
        guard parts.count > 1, let first = parts.first, let last = parts.last else { return nil }
        return "\(first)\(last)@\(domain)"
    }

    private static func validate(_ key: String) throws {
        guard key.range(of: #"^[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}$"#, options: .regularExpression) != nil else {
            throw WatcherError.setup("Clave de Jira inválida: \(key)")
        }
    }
}

private struct RosterMember {
    let username: String
    let name: String
    var teams: [String]
}
