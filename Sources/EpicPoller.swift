import Foundation

/// Watches every epic in `config.jira.epics`. Owns its timer and seen store; every touch of them happens on `queue`.
final class EpicPoller {
    private var config: Config
    private let client: JiraClient
    private let notifier: Notifier
    private let list: TicketList
    private var store: EpicSeenStore
    private let queue = DispatchQueue(label: "app.reviewwatcher.epic")
    private var timer: DispatchSourceTimer?
    private var isPaused = false
    /// Moves and assignments made from the menu, by ticket key, until a poll sees them land.
    private var ownActions: [String: [TicketAction]] = [:]
    private var projectStatuses: [String: Set<TicketStatus>] = [:]
    /// The last branch each epic loaded, still shown above the error while a later poll of it fails.
    private var lastBranches: [String: EpicBranch] = [:]

    private static let statusSampleSize = 200
    /// Minutes added to the "updated since" window, for clock skew and edits landing while a poll runs.
    private static let windowMarginMinutes = 2

    private var jira: JiraConfig { config.jira }

    init(config: Config, client: JiraClient, notifier: Notifier, list: TicketList) {
        self.config = config
        self.client = client
        self.notifier = notifier
        self.list = list
        self.store = EpicSeenStore.load()
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.schedule(deadline: .now(), repeating: config.pollInterval)
            self.timer = timer
            timer.resume()
            if jira.isSetUp {
                Log.write("following epics \(Self.describe(jira.epics)) on \(jira.site)")
            }
        }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self, let timer, !isPaused else { return }
            isPaused = true
            timer.suspend()
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, let timer, isPaused else { return }
            isPaused = false
            timer.schedule(deadline: .now(), repeating: config.pollInterval)
            timer.resume()
        }
    }

    func apply(_ newConfig: Config) {
        queue.async { [weak self] in
            guard let self else { return }
            let isNewInterval = newConfig.pollInterval != config.pollInterval
            let isNewFollowing = newConfig.jira.epics != jira.epics
            config = newConfig
            if isNewFollowing {
                Log.write("following epics \(Self.describe(newConfig.jira.epics))")
                poll()
            }
            guard isNewInterval, let timer, !isPaused else { return }
            timer.schedule(deadline: .now() + newConfig.pollInterval, repeating: newConfig.pollInterval)
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.poll() }
    }

    func acknowledge(_ action: TicketAction, on key: String) {
        queue.async { [weak self] in self?.ownActions[key, default: []].append(action) }
    }

    private func poll() {
        guard jira.isSetUp else {
            list.showNotSetUp()
            return
        }
        let epicKeys = jira.epics
        do {
            try sampleStatuses(ofProjects: Set(epicKeys.map(Ticket.project(of:))))
        } catch {
            Log.write("epic poll failed: \(error.localizedDescription)")
            list.showFailure(error)
            return
        }

        let startedAt = Date()
        let known = store
        let outcomes = concurrently(epicKeys) { [client] key in
            try Self.fetch(key, known: known.epics[key], client: client)
        }
        var sections: [EpicSection] = []
        var epics: [String: EpicSeenStore.EpicState] = [:]
        var announcements: [Announcement] = []
        for (key, outcome) in zip(epicKeys, outcomes) {
            switch outcome {
            case .success(let fetched):
                let reconciled = reconcile(fetched, known: known.epics[key], polledAt: startedAt)
                epics[key] = reconciled.state
                announcements += reconciled.announcements
                lastBranches[key] = fetched.branch
                sections.append(EpicSection(key: key, branch: fetched.branch, failure: nil))
            case .failure(let error):
                Log.write("epic \(key) poll failed: \(error.localizedDescription)")
                epics[key] = known.epics[key]
                sections.append(EpicSection(key: key, branch: lastBranches[key], failure: error.localizedDescription))
            }
        }

        // Rebuilding the map drops epics no longer followed, so following one again starts silent.
        store = EpicSeenStore(epics: epics)
        lastBranches = lastBranches.filter { epicKeys.contains($0.key) }
        let trackedKeys = Set(epics.values.flatMap(\.tickets.keys))
        ownActions = ownActions.filter { trackedKeys.contains($0.key) }
        do {
            try store.save()
        } catch {
            Log.write("could not persist state to \(Paths.epicStateFile.path): \(error.localizedDescription)")
        }

        list.show(sections, statuses: transitionTargets(seenIn: sections))
        for announcement in announcements {
            let headlines = announcement.changes.map {
                $0.headline(for: announcement.ticket, epic: announcement.epicKey, me: jira.email)
            }
            Log.write("\(announcement.ticket.key): " + headlines.joined(separator: " · "))
            notifier.post(announcement.ticket, epic: announcement.epicKey, changes: announcement.changes, jira: jira)
        }
    }

    /// Reads one epic's tree. Runs alongside the other epics' reads, so it touches nothing but its arguments.
    private static func fetch(_ epicKey: String, known: EpicSeenStore.EpicState?, client: JiraClient) throws -> FetchedEpic {
        let tree = try client.search("key = \(epicKey) OR parent = \(epicKey)")
        guard let epic = tree.first(where: { $0.key == epicKey }) else {
            throw WatcherError.setup("\(epicKey) does not exist, or you cannot see it")
        }
        let children = tree.filter { $0.key != epicKey }
        let childKeys = children.map(\.key).joined(separator: ", ")
        let subtasks = children.isEmpty ? [] : try client.search("parent in (\(childKeys))")
        let branchJQL = children.isEmpty
            ? "key = \(epicKey) OR parent = \(epicKey)"
            : "key = \(epicKey) OR parent in (\(epicKey), \(childKeys))"

        let tickets = tree + subtasks
        let unseen = tickets.map(\.key).filter { known?.tickets[$0] == nil }
        let changed = try known.map { try recentlyChangedKeys(matching: branchJQL, since: $0.polledAt, client: client) } ?? []
        let activities = try client.activities(of: Array(Set(unseen + changed)))

        var parentKeys: [String: String] = [:]
        for ticket in tickets {
            parentKeys[ticket.key] = activities[ticket.key]?.parentKey ?? known?.tickets[ticket.key]?.parentKey
        }
        let branch = try EpicBranch(epic: epic, children: children, subtasks: subtasks, parentKeys: parentKeys)
        return FetchedEpic(branch: branch, tickets: tickets, activities: activities, parentKeys: parentKeys)
    }

    /// Search will not return `updated`, but it filters on it: what changed since the last poll is read in full.
    private static func recentlyChangedKeys(matching branchJQL: String, since polledAt: Date,
                                            client: JiraClient) throws -> [String] {
        let minutes = Int((Date().timeIntervalSince(polledAt) / 60).rounded(.up)) + windowMarginMinutes
        return try client.search("(\(branchJQL)) AND updated >= -\(minutes)m").map(\.key)
    }

    /// acli cannot list a ticket's transitions, so the menu offers every status the project used lately;
    /// Jira refuses the ones the workflow does not allow from where the ticket stands.
    private func sampleStatuses(ofProjects projects: Set<String>) throws {
        for project in projects where projectStatuses[project] == nil {
            let sample = try client.search("project = \(project) ORDER BY updated DESC", limit: Self.statusSampleSize)
            projectStatuses[project] = Set(sample.map(\.status))
        }
    }

    private func transitionTargets(seenIn sections: [EpicSection]) -> [String: [TicketStatus]] {
        var statuses = projectStatuses
        for branch in sections.compactMap(\.branch) {
            for ticket in [branch.epic] + branch.workItems {
                statuses[ticket.project, default: []].insert(ticket.status)
            }
        }
        let workflowOrder = TicketStatus.Category.allCases
        return statuses.mapValues { projectStatuses in
            projectStatuses.sorted { lhs, rhs in
                let left = workflowOrder.firstIndex(of: lhs.category) ?? 0
                let right = workflowOrder.firstIndex(of: rhs.category) ?? 0
                guard left == right else { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func reconcile(_ fetched: FetchedEpic, known: EpicSeenStore.EpicState?,
                           polledAt: Date) -> (state: EpicSeenStore.EpicState, announcements: [Announcement]) {
        var announcements: [Announcement] = []
        var tickets: [String: EpicSeenStore.TicketState] = [:]
        for ticket in fetched.tickets {
            let previous = known?.tickets[ticket.key]
            let activity = fetched.activities[ticket.key]
            let changes: [TicketChange]
            if let previous {
                changes = self.changes(to: ticket, since: previous, activity: activity)
            } else {
                changes = known != nil && jira.notifyOnNewTicket ? [.added] : []
            }
            if !changes.isEmpty {
                announcements.append(Announcement(ticket: ticket, epicKey: fetched.branch.epic.key, changes: changes))
            }
            tickets[ticket.key] = EpicSeenStore.TicketState(
                status: ticket.status.name,
                assigneeAccountID: ticket.assignee?.accountID,
                parentKey: fetched.parentKeys[ticket.key],
                latestCommentID: activity?.comments.map(\.id).max() ?? previous?.latestCommentID
            )
        }
        return (EpicSeenStore.EpicState(polledAt: polledAt, tickets: tickets), announcements)
    }

    private func changes(to ticket: Ticket, since previous: EpicSeenStore.TicketState,
                         activity: TicketActivity?) -> [TicketChange] {
        var changes: [TicketChange] = []
        if previous.status != ticket.status.name,
           !consumeOwnAction(.move(to: ticket.status.name), on: ticket.key),
           jira.notifyOnStatusChange {
            changes.append(.statusChanged(from: previous.status))
        }
        if previous.assigneeAccountID != ticket.assignee?.accountID,
           !consumeOwnAction(ownAssignment(explaining: ticket), on: ticket.key),
           jira.notifyOnAssigneeChange {
            changes.append(.reassigned)
        }
        if jira.notifyOnComment, let activity {
            let newComments = activity.comments.filter {
                $0.id > (previous.latestCommentID ?? 0) && !$0.author.isSomeone(withEmail: jira.email)
            }
            if !newComments.isEmpty {
                changes.append(.commented(newComments))
            }
        }
        return changes
    }

    private func ownAssignment(explaining ticket: Ticket) -> TicketAction? {
        if ticket.assignee == nil { return .unassign }
        return ticket.isAssigned(to: jira.email) ? .assignToMe : nil
    }

    private func consumeOwnAction(_ action: TicketAction?, on key: String) -> Bool {
        guard let action, let index = ownActions[key]?.firstIndex(of: action) else { return false }
        ownActions[key]?.remove(at: index)
        return true
    }

    private static func describe(_ epics: [String]) -> String {
        epics.isEmpty ? "none" : epics.joined(separator: ", ")
    }
}

private struct FetchedEpic {
    let branch: EpicBranch
    let tickets: [Ticket]
    let activities: [String: TicketActivity]
    let parentKeys: [String: String]
}

private struct Announcement {
    let ticket: Ticket
    let epicKey: String
    let changes: [TicketChange]
}
