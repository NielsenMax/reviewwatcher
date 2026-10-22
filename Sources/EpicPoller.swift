import Foundation

/// Watches the epic in `config.jira`. Owns its timer and seen store; every touch of them happens on `queue`.
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
    private var projectStatuses: (project: String, statuses: Set<TicketStatus>)?

    private static let statusSampleSize = 200
    /// Minutes added to the "updated since" window, for clock skew and edits landing while a poll runs.
    private static let windowMarginMinutes = 2

    private var jira: JiraConfig { config.jira }

    init(config: Config, client: JiraClient, notifier: Notifier, list: TicketList) {
        self.config = config
        self.client = client
        self.notifier = notifier
        self.list = list
        self.store = EpicSeenStore.load(for: config.jira.epic)
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.schedule(deadline: .now(), repeating: config.pollInterval)
            self.timer = timer
            timer.resume()
            if !jira.epic.isEmpty {
                Log.write("watching epic \(jira.epic) on \(jira.site)")
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
            let isNewEpic = newConfig.jira.epic != jira.epic
            config = newConfig
            if isNewEpic {
                Log.write("watching epic \(newConfig.jira.epic)")
                list.showWaiting()
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
        guard let project = jira.project else {
            list.showNoEpic()
            return
        }
        if store.epic != jira.epic {
            store = .fresh(for: jira.epic)
            ownActions = [:]
        }
        do {
            let startedAt = Date()
            let polled = try readBranch()
            list.show(polled.branch, statuses: try transitionTargets(in: project, seenIn: polled))
            for (ticket, changes) in reconcile(polled, polledAt: startedAt) {
                Log.write("\(ticket.key): " + changes.map { $0.headline(for: ticket, epic: jira.epic, me: jira.email) }
                    .joined(separator: " · "))
                notifier.post(ticket, changes: changes, jira: jira)
            }
        } catch {
            Log.write("epic poll failed: \(error.localizedDescription)")
            list.showFailure(error)
        }
    }

    private func readBranch() throws -> PolledBranch {
        let epicKey = jira.epic
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
        let unseen = tickets.map(\.key).filter { store.tickets[$0] == nil }
        let changed = try recentlyChangedKeys(matching: branchJQL)
        let activities = try client.activities(of: Array(Set(unseen + changed)))

        var parentKeys: [String: String] = [:]
        for ticket in tickets {
            parentKeys[ticket.key] = activities[ticket.key]?.parentKey ?? store.tickets[ticket.key]?.parentKey
        }
        let branch = try EpicBranch(epic: epic, children: children, subtasks: subtasks, parentKeys: parentKeys)
        return PolledBranch(branch: branch, tickets: tickets, activities: activities, parentKeys: parentKeys)
    }

    /// Search will not return `updated`, but it filters on it: what changed since the last poll is read in full.
    private func recentlyChangedKeys(matching branchJQL: String) throws -> [String] {
        guard let polledAt = store.polledAt else { return [] }
        let minutes = Int((Date().timeIntervalSince(polledAt) / 60).rounded(.up)) + Self.windowMarginMinutes
        return try client.search("(\(branchJQL)) AND updated >= -\(minutes)m").map(\.key)
    }

    /// acli cannot list a ticket's transitions, so the menu offers every status the project uses lately;
    /// Jira refuses the ones the workflow does not allow from where the ticket stands.
    private func transitionTargets(in project: String, seenIn polled: PolledBranch) throws -> [TicketStatus] {
        if projectStatuses?.project != project {
            let sample = try client.recentlyUpdated(in: project, limit: Self.statusSampleSize)
            projectStatuses = (project, Set(sample.map(\.status)))
        }
        let statuses = (projectStatuses?.statuses ?? []).union(polled.tickets.map(\.status))
        let workflowOrder = TicketStatus.Category.allCases
        return statuses.sorted { lhs, rhs in
            let left = workflowOrder.firstIndex(of: lhs.category) ?? 0
            let right = workflowOrder.firstIndex(of: rhs.category) ?? 0
            guard left == right else { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func reconcile(_ polled: PolledBranch, polledAt: Date) -> [(Ticket, [TicketChange])] {
        let isSeeded = store.polledAt != nil
        var announcements: [(Ticket, [TicketChange])] = []
        var current: [String: EpicSeenStore.TicketState] = [:]
        for ticket in polled.tickets {
            let previous = store.tickets[ticket.key]
            let activity = polled.activities[ticket.key]
            let changes: [TicketChange]
            if let previous {
                changes = self.changes(to: ticket, since: previous, activity: activity)
            } else {
                changes = isSeeded && jira.notifyOnNewTicket ? [.added] : []
            }
            if !changes.isEmpty {
                announcements.append((ticket, changes))
            }
            current[ticket.key] = EpicSeenStore.TicketState(
                status: ticket.status.name,
                assigneeAccountID: ticket.assignee?.accountID,
                parentKey: polled.parentKeys[ticket.key],
                latestCommentID: activity?.comments.map(\.id).max() ?? previous?.latestCommentID
            )
        }

        // Rebuilding the map rather than merging drops tickets moved out of the branch or deleted.
        store = EpicSeenStore(epic: jira.epic, polledAt: polledAt, tickets: current)
        ownActions = ownActions.filter { current[$0.key] != nil }
        do {
            try store.save()
        } catch {
            Log.write("could not persist state to \(Paths.epicStateFile.path): \(error.localizedDescription)")
        }
        return announcements
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
}

private struct PolledBranch {
    let branch: EpicBranch
    let tickets: [Ticket]
    let activities: [String: TicketActivity]
    let parentKeys: [String: String]
}
