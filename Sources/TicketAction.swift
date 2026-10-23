import Foundation

enum TicketAction: Hashable {
    case move(to: String)
    case assignToMe
    case unassign

    var title: String {
        switch self {
        case .move(let status): return "Move to \(status)"
        case .assignToMe: return "Assign to me"
        case .unassign: return "Unassign"
        }
    }

    func run(on ticket: Ticket, client: JiraClient) throws -> String {
        switch self {
        case .move(let status):
            try client.transition(ticket.key, to: status)
            return "Moved to \(status)"
        case .assignToMe:
            try client.assignToMe(ticket.key)
            return "Assigned to you"
        case .unassign:
            try client.unassign(ticket.key)
            return "Unassigned"
        }
    }
}
