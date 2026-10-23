import Foundation

/// An epic and everything filed under it: its children, and their subtasks.
struct EpicBranch {
    let epic: Ticket
    let children: [Ticket]
    let subtasksByParent: [String: [Ticket]]

    struct Row: Identifiable {
        let ticket: Ticket
        let isSubtask: Bool

        var id: String { ticket.key }
    }

    init(epic: Ticket, children: [Ticket], subtasks: [Ticket], parentKeys: [String: String]) throws {
        self.epic = epic
        self.children = Self.ordered(children)
        var grouped: [String: [Ticket]] = [:]
        for subtask in subtasks {
            guard let parentKey = parentKeys[subtask.key] else {
                throw WatcherError.setup("\(subtask.key) was found under \(epic.key) but its parent is unknown")
            }
            grouped[parentKey, default: []].append(subtask)
        }
        subtasksByParent = grouped.mapValues(Self.ordered)
    }

    var workItems: [Ticket] {
        children + children.flatMap { subtasksByParent[$0.key] ?? [] }
    }

    var openCount: Int {
        workItems.filter { $0.status.category != .done }.count
    }

    /// A finished child stays listed while any of its subtasks is still open.
    func rows(includingDone: Bool) -> [Row] {
        children.flatMap { child -> [Row] in
            let subtasks = (subtasksByParent[child.key] ?? []).filter { includingDone || $0.status.category != .done }
            guard includingDone || child.status.category != .done || !subtasks.isEmpty else { return [] }
            return [Row(ticket: child, isSubtask: false)] + subtasks.map { Row(ticket: $0, isSubtask: true) }
        }
    }

    /// Work under way first, then what waits, then what is finished; keys in creation order within each.
    private static func ordered(_ tickets: [Ticket]) -> [Ticket] {
        tickets.sorted { lhs, rhs in
            let left = listRank(lhs.status.category)
            let right = listRank(rhs.status.category)
            guard left == right else { return left < right }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
    }

    private static func listRank(_ category: TicketStatus.Category) -> Int {
        switch category {
        case .inProgress: return 0
        case .toDo: return 1
        case .done: return 2
        }
    }
}
