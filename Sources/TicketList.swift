import Foundation

/// What the popover's Epic tab shows. Owned by the main queue; the poller feeds it from its own.
final class TicketList: ObservableObject {
    enum PollState {
        case notSetUp
        case noEpic
        case waiting
        case updated(Date)
        case failed(String)
    }

    enum Progress {
        case working
        case done(String)
        case failed(String)
    }

    @Published private(set) var branch: EpicBranch?
    @Published private(set) var statuses: [TicketStatus] = []
    @Published private(set) var pollState = PollState.waiting
    @Published private(set) var progress: [String: Progress] = [:]

    let email: String
    private let client: JiraClient

    /// Assigned once the poller exists, since the poller is built around this list.
    var refresh: () -> Void = {}
    var acknowledge: (TicketAction, String) -> Void = { _, _ in }

    init(email: String, client: JiraClient) {
        self.email = email
        self.client = client
    }

    func show(_ branch: EpicBranch, statuses: [TicketStatus]) {
        DispatchQueue.main.async {
            let shownKeys = Set(branch.workItems.map(\.key))
            self.branch = branch
            self.statuses = statuses
            self.progress = self.progress.filter { key, progress in
                guard shownKeys.contains(key) else { return false }
                if case .done = progress { return false }
                return true
            }
            self.pollState = .updated(Date())
        }
    }

    func showWaiting() {
        DispatchQueue.main.async {
            self.branch = nil
            self.progress = [:]
            self.pollState = .waiting
        }
    }

    func showNotSetUp() {
        DispatchQueue.main.async {
            self.branch = nil
            self.pollState = .notSetUp
        }
    }

    func showNoEpic() {
        DispatchQueue.main.async {
            self.branch = nil
            self.pollState = .noEpic
        }
    }

    func showFailure(_ error: Error) {
        DispatchQueue.main.async {
            self.pollState = .failed(error.localizedDescription)
        }
    }

    func moveTargets(for ticket: Ticket) -> [TicketStatus] {
        statuses.filter { $0.name != ticket.status.name }
    }

    func assignment(for ticket: Ticket) -> TicketAction {
        ticket.isAssigned(to: email) ? .unassign : .assignToMe
    }

    func trigger(_ action: TicketAction, on ticket: Ticket) {
        progress[ticket.key] = .working
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let outcome = Result { try action.run(on: ticket, client: client) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let summary):
                    Log.write("\(summary): \(ticket.key)")
                    self.progress[ticket.key] = .done(summary)
                    self.acknowledge(action, ticket.key)
                case .failure(let error):
                    Log.write("\(action.title) failed for \(ticket.key): \(error.localizedDescription)")
                    self.progress[ticket.key] = .failed(error.localizedDescription)
                }
                self.refresh()
            }
        }
    }
}
