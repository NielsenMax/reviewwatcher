import Foundation

enum TicketChange {
    case added
    case statusChanged(from: String)
    case reassigned
    case commented([TicketActivity.Comment])

    func headline(for ticket: Ticket, epic: String, me email: String) -> String {
        switch self {
        case .added:
            return "New in \(epic)"
        case .statusChanged(let previous):
            return "\(previous) → \(ticket.status.name)"
        case .reassigned:
            guard let assignee = ticket.assignee else { return "Unassigned" }
            return ticket.isAssigned(to: email) ? "Assigned to you" : "Assigned to \(assignee.displayName)"
        case .commented(let comments):
            guard comments.count == 1, let comment = comments.first else { return "\(comments.count) new comments" }
            return "\(comment.author.displayName) commented"
        }
    }
}
