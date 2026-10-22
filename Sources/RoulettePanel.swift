import SwiftUI

/// The side panel: the pool, the players and the log of past spins.
struct RoulettePanel: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(RouletteTab.allCases, id: \.self) { tab in
                    PanelTab(title: title(of: tab), count: count(of: tab), isSelected: model.tab == tab) {
                        model.choose(tab: tab)
                    }
                }
            }
            Rectangle().fill(Casino.line).frame(height: 1)
            ScrollView {
                Group {
                    switch model.tab {
                    case .pool: PoolPane(model: model)
                    case .players: PlayersPane(model: model)
                    case .log: LogPane(model: model)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(Casino.panel))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Casino.line))
    }

    private func title(of tab: RouletteTab) -> String {
        switch tab {
        case .pool: return "Pozo"
        case .players: return "Jugadores"
        case .log: return "Planilla"
        }
    }

    private func count(of tab: RouletteTab) -> Int? {
        switch tab {
        case .pool: return model.loading.contains(.pool) ? nil : model.tickets.count
        case .players: return model.loading.contains(.players) ? nil : model.players.filter(\.canPlay).count
        case .log: return model.loading.contains(.log) ? nil : model.assignments.count
        }
    }
}

private struct PanelTab: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.44)
                    .foregroundStyle(isSelected ? Casino.ivory.color() : Casino.chalk.color())
                if let count {
                    Text(String(count))
                        .font(Casino.mono(12))
                        .foregroundStyle(Casino.brass.color())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(isSelected ? Casino.brass.color() : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PoolPane: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Búsqueda de Jira (JQL)")
                TextEditor(text: $model.jqlDraft)
                    .font(Casino.mono(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 64, maxHeight: 96)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.28)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Casino.line))
                HStack(spacing: 10) {
                    Text("Lo que devuelva esta búsqueda entra al pozo.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Casino.chalk.color())
                    Spacer()
                    Button("Actualizar", action: model.loadPool)
                        .buttonStyle(CasinoButtonStyle())
                    Button("Buscar", action: model.searchPool)
                        .buttonStyle(CasinoButtonStyle(kind: .primary))
                }
                .disabled(model.loading.contains(.pool))
            }
            HStack(spacing: 12) {
                PillPicker(options: [
                    PillOption(value: PoolGrouping.list, title: "Lista"),
                    PillOption(value: PoolGrouping.epic, title: "Épica"),
                    PillOption(value: PoolGrouping.tag, title: "Tag"),
                ], selection: model.grouping, choose: model.choose(grouping:))
                .fixedSize()
                Text(groupingHint)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Casino.chalk.color())
            }
            tickets
        }
    }

    private var groupingHint: String {
        if model.grouping == .tag { return "Un ticket con varios tags aparece en cada uno." }
        if model.grouping == .epic, model.loading.contains(.epics) { return "Buscando las épicas en Jira…" }
        return ""
    }

    @ViewBuilder
    private var tickets: some View {
        if model.loading.contains(.pool) {
            EmptyNote(text: "Buscando en Jira…")
        } else if let error = model.errors[.pool] {
            EmptyNote(text: error, isError: true)
        } else if model.tickets.isEmpty {
            EmptyNote(text: "La búsqueda no devolvió tickets. Podés girar igual: sale un nombre y no se asigna.")
        } else if model.grouping == .list || (model.grouping == .epic && model.loading.contains(.epics)) {
            ticketRows(model.tickets, groupLabel: nil)
        } else if model.grouping == .epic, let error = model.errors[.epics] {
            VStack(alignment: .leading, spacing: 4) {
                EmptyNote(text: "No pude traer las épicas: \(error)", isError: true)
                ticketRows(model.tickets, groupLabel: nil)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.poolGroups) { group in
                    GroupBlock(model: model, group: group)
                }
            }
        }
    }

    private func ticketRows(_ tickets: [Ticket], groupLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tickets) { ticket in
                PoolTicketRow(model: model, ticket: ticket, groupLabel: groupLabel)
            }
        }
    }
}

private struct GroupBlock: View {
    @ObservedObject var model: RouletteModel
    let group: PoolGroup

    var body: some View {
        let isOpen = model.isOpen(group)
        let isPlaying = model.scope?.id == group.id
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button { model.toggle(group) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("▸")
                            .foregroundStyle(Casino.chalk.color())
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .frame(width: 10)
                        if let key = group.epicKey {
                            Text(key)
                                .font(Casino.mono(13, weight: .bold))
                                .foregroundStyle(Casino.brass.color())
                        }
                        Text(group.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isPlaying ? Casino.brass.color() : Casino.ivory.color())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(group.tickets.count))
                            .font(Casino.mono(12))
                            .foregroundStyle(Casino.brass.color())
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(isPlaying ? "En juego" : "Sortear") { model.play(group) }
                    .buttonStyle(ChipButtonStyle(isOn: isPlaying))
                    .help(isPlaying ? "Volver a sortear todo el pozo" : "Cada giro se lleva el siguiente ticket de este grupo")
                    .disabled(model.isSpinning)
                if let key = group.epicKey {
                    JiraLink(url: model.browseURL(for: key), help: "Abrir épica en Jira")
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(isPlaying ? Casino.brass.color() : Casino.line).frame(height: 1)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.tickets) { ticket in
                        PoolTicketRow(model: model, ticket: ticket, groupLabel: group.label)
                    }
                }
            }
        }
    }
}

private struct PoolTicketRow: View {
    @ObservedObject var model: RouletteModel
    let ticket: Ticket
    let groupLabel: String?

    var body: some View {
        let isSelected = ticket.key == model.selectedKey
        let epic = model.grouping == .epic ? nil : model.epic(of: ticket)
        let labels = model.grouping == .tag ? ticket.labels.filter { $0 != groupLabel } : ticket.labels
        HStack(alignment: .top, spacing: 8) {
            Button { model.select(ticket) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(ticket.key)
                            .font(Casino.mono(13, weight: .bold))
                            .foregroundStyle(Casino.brass.color())
                        if let priority = ticket.priority {
                            PriorityTag(priority: priority, isHigh: model.isHighPriority(ticket))
                        }
                        if isSelected { InPlayBadge() }
                    }
                    Text(ticket.summary.isEmpty ? "Sin título" : ticket.summary)
                        .fixedSize(horizontal: false, vertical: true)
                    if epic != nil || !labels.isEmpty {
                        FlowLayout(spacing: 4) {
                            if let epic {
                                TableTag(text: epic.summary.isEmpty ? epic.key : epic.summary, tone: .epic)
                                    .help("Épica \(epic.key)")
                            }
                            ForEach(labels, id: \.self) { TableTag(text: $0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            JiraLink(url: model.browseURL(for: ticket.key), help: "Abrir \(ticket.key) en Jira")
                .padding(.top, 6)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Casino.brass.color(opacity: 0.08) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Casino.brass.color(opacity: 0.55) : .clear))
    }
}

private struct PlayersPane: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("Salen de los equipos de GitLab. El switch los saca de la mesa (licencia, guardia).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Casino.chalk.color())
                Spacer()
                Button("Actualizar", action: model.loadPlayers)
                    .buttonStyle(CasinoButtonStyle())
                    .disabled(model.loading.contains(.players))
            }
            if model.loading.contains(.players) {
                EmptyNote(text: "Leyendo los equipos de GitLab y cruzando con Jira…")
            } else if let error = model.errors[.players] {
                EmptyNote(text: error, isError: true)
            } else if model.players.isEmpty {
                EmptyNote(text: "No encontré integrantes en los equipos de GitLab.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.players.sorted { $0.name.compare($1.name, locale: Locale(identifier: "es")) == .orderedAscending }) { player in
                        PlayerRow(model: model, player: player)
                    }
                }
            }
        }
    }
}

private struct PlayerRow: View {
    @ObservedObject var model: RouletteModel
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { player.canPlay }, set: { _ in model.toggleActive(player) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Casino.verde.color())
                .disabled(player.jira == nil || model.isSpinning)
                .help(player.jira == nil ? "Sin usuario de Jira: no se le puede asignar" : player.isActive ? "En la mesa" : "Afuera")
            FlowLayout(spacing: 6) {
                Text(player.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(player.canPlay ? Casino.ivory.color() : Casino.chalk.color())
                    .strikethrough(!player.canPlay, color: Casino.chalk.color(opacity: 0.5))
                ForEach(player.teams, id: \.self) { TableTag(text: $0) }
                if player.jira == nil { TableTag(text: "sin usuario de Jira", tone: .warn) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(player.jira == nil ? "—" : "\(player.openLoad) abiertos")
                .font(Casino.mono(12))
                .monospacedDigit()
                .foregroundStyle(Casino.chalk.color())
                .help("Tickets abiertos asignados")
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 10)
    }
}

private struct LogPane: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("Lo que salió en la ruleta y quedó asignado en Jira.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Casino.chalk.color())
                Spacer()
                Button("Copiar lo de hoy", action: model.copyToday)
                    .buttonStyle(CasinoButtonStyle())
                    .disabled(!model.hasAssignmentsToday)
            }
            if model.loading.contains(.log) {
                EmptyNote(text: "Cargando la planilla…")
            } else if let error = model.errors[.log] {
                EmptyNote(text: error, isError: true)
            } else if model.assignments.isEmpty {
                EmptyNote(text: "Todavía no hay tiradas. Lo que salga en la ruleta y se asigne en Jira queda anotado acá.")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(days, id: \.title) { day in
                        Text(day.title.uppercased())
                            .font(Casino.mono(11))
                            .tracking(1.76)
                            .foregroundStyle(Casino.chalk.color())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, day.title == days.first?.title ? 0 : 12)
                            .padding(.bottom, 4)
                            .overlay(alignment: .bottom) { Rectangle().fill(Casino.line).frame(height: 1) }
                            .padding(.bottom, 4)
                        ForEach(day.assignments) { assignment in
                            if model.confirmingUndo == assignment.key {
                                UndoConfirmation(model: model, assignment: assignment)
                            } else {
                                AssignmentRow(model: model, assignment: assignment)
                            }
                        }
                    }
                }
            }
        }
    }

    private var days: [(title: String, assignments: [Assignment])] {
        var grouped: [(title: String, assignments: [Assignment])] = []
        for assignment in model.recentAssignments {
            let title = Self.dayTitle(assignment.date)
            if grouped.last?.title == title {
                grouped[grouped.count - 1].assignments.append(assignment)
            } else {
                grouped.append((title, [assignment]))
            }
        }
        return grouped
    }

    private static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hoy" }
        if Calendar.current.isDateInYesterday(date) { return "Ayer" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return formatter.string(from: date)
    }
}

private struct AssignmentRow: View {
    @ObservedObject var model: RouletteModel
    let assignment: Assignment
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(assignment.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Casino.mono(12))
                .monospacedDigit()
                .foregroundStyle(Casino.chalk.color())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button { model.browseURL(for: assignment.key).map { openURL($0) } } label: {
                        Text(assignment.key)
                            .font(Casino.mono(13, weight: .bold))
                            .foregroundStyle(Casino.brass.color())
                    }
                    .buttonStyle(.plain)
                    (Text("→ ").foregroundColor(Casino.chalk.color()) + Text(assignment.name).fontWeight(.semibold))
                }
                Text(assignment.summary.isEmpty ? "Sin título" : assignment.summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Casino.chalk.color())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.confirmingUndo = assignment.key } label: {
                Text("↩").font(.system(size: 15)).foregroundStyle(Casino.chalk.color()).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Desasignar en Jira y devolver al pozo")
            .disabled(model.isSpinning)
        }
        .padding(.vertical, 8)
        .padding(.leading, 6)
        .padding(.trailing, 4)
    }
}

private struct UndoConfirmation: View {
    @ObservedObject var model: RouletteModel
    let assignment: Assignment

    var body: some View {
        HStack(spacing: 8) {
            Text("¿Desasignar \(assignment.key) de \(assignment.name) en Jira y devolverlo al pozo?")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Desasignar") {
                model.confirmingUndo = nil
                model.unassign(assignment.key)
            }
            .buttonStyle(CasinoButtonStyle(kind: .danger))
            Button("No") { model.confirmingUndo = nil }
                .buttonStyle(CasinoButtonStyle(kind: .ghost))
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Casino.rojo.color(opacity: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Casino.rojo.color(opacity: 0.5)))
    }
}
