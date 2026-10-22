import SwiftUI

struct TicketListView: View {
    @ObservedObject var list: TicketList
    @ObservedObject var settings: Settings
    let openSettings: () -> Void
    @Environment(\.openURL) private var openURL

    private static let maxRowsHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                epicTitle
                pollSummary.font(.caption).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Toggle(isOn: $settings.config.jira.showsDoneTickets) { Image(systemName: "checkmark.circle") }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(settings.config.jira.showsDoneTickets ? "Hide finished tickets" : "Show finished tickets")
            Button { list.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh now")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var epicTitle: some View {
        if let epic = list.branch?.epic {
            Button { open(epic.key) } label: {
                Text("\(epic.key) · \(epic.summary)").font(.headline).lineLimit(1).truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Open \(epic.key) in Jira")
        } else {
            Text(settings.config.jira.epic.isEmpty ? "Epic" : settings.config.jira.epic).font(.headline)
        }
    }

    @ViewBuilder
    private var pollSummary: some View {
        switch list.pollState {
        case .notSetUp:
            Text("Jira not set up").foregroundStyle(.secondary)
        case .noEpic:
            Text("No epic chosen").foregroundStyle(.secondary)
        case .waiting:
            Text("Loading…").foregroundStyle(.secondary)
        case .updated(let date):
            let total = list.branch?.workItems.count ?? 0
            let done = total - (list.branch?.openCount ?? 0)
            Text("\(done) of \(total) done · updated \(date.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red).help(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .notSetUp = list.pollState {
            placeholder("Log in with acli jira auth login, then run install.sh again.")
        } else if case .noEpic = list.pollState {
            VStack(spacing: 8) {
                Text("Choose the epic to watch.").foregroundStyle(.secondary)
                Button("Open Settings", action: openSettings)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let branch = list.branch {
            let rows = branch.rows(includingDone: settings.config.jira.showsDoneTickets)
            if rows.isEmpty {
                placeholder(branch.workItems.isEmpty ? "Nothing filed under \(branch.epic.key) yet."
                                                      : "Everything under \(branch.epic.key) is done.")
            } else {
                // The popover takes the ideal size, and a scroll view's ideal height is its content's.
                ScrollView { rowStack(rows) }
                    .frame(maxHeight: Self.maxRowsHeight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if case .waiting = list.pollState {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            placeholder("Could not load the epic.")
        }
    }

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func rowStack(_ rows: [EpicBranch.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                TicketRow(row: row, list: list, open: open)
                if row.id != rows.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
    }

    private func open(_ key: String) {
        if let url = settings.config.jira.browseURL(for: key) { openURL(url) }
    }
}

private struct TicketRow: View {
    let row: EpicBranch.Row
    @ObservedObject var list: TicketList
    let open: (String) -> Void

    private var ticket: Ticket { row.ticket }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                TicketStatusDot(category: ticket.status.category).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ticket.summary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                TicketStatusChip(text: ticket.status.name)
                Spacer(minLength: 4)
                Button { open(ticket.key) } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Open in Jira")
                TicketActionButtons(ticket: ticket, list: list)
            }
            .padding(.leading, 16)
            TicketActionFailure(key: ticket.key, list: list).padding(.leading, 16)
        }
        .padding(.leading, row.isSubtask ? 34 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var details: String {
        [ticket.key, ticket.type, ticket.assignee?.displayName ?? "Unassigned", ticket.priority]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct TicketActionButtons: View {
    let ticket: Ticket
    @ObservedObject var list: TicketList

    var body: some View {
        switch list.progress[ticket.key] {
        case .working:
            ProgressView().controlSize(.small)
        case .done(let summary):
            Text(summary).font(.caption).foregroundStyle(.secondary)
        case .failed, nil:
            HStack(spacing: 6) {
                let targets = list.moveTargets(for: ticket)
                Menu("Move") {
                    ForEach(targets, id: \.self) { status in
                        Button("\(status.category.emoji) \(status.name)") {
                            list.trigger(.move(to: status.name), on: ticket)
                        }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(targets.isEmpty)
                let assignment = list.assignment(for: ticket)
                Button(assignment.title) { list.trigger(assignment, on: ticket) }
                    .controlSize(.small)
            }
        }
    }
}

private struct TicketActionFailure: View {
    let key: String
    @ObservedObject var list: TicketList

    var body: some View {
        if case .failed(let message) = list.progress[key] {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TicketStatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct TicketStatusDot: View {
    let category: TicketStatus.Category

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch category {
        case .toDo: return .secondary.opacity(0.5)
        case .inProgress: return .blue
        case .done: return .green
        }
    }
}
