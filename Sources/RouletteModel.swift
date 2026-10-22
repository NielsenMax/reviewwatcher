import AppKit
import Combine

enum PoolGrouping: String, CaseIterable {
    case list = "lista"
    case epic = "epica"
    case tag
}

enum RouletteMode: String {
    case even = "pareja"
    case weighted = "compensada"
}

enum RouletteTab: String, CaseIterable {
    case pool = "pozo"
    case players = "jugadores"
    case log = "planilla"
}

enum RouletteLoad: Hashable {
    case players, pool, log, epics
}

struct RouletteScope: Equatable {
    let grouping: PoolGrouping
    let id: String
    let title: String
}

struct PoolGroup: Identifiable {
    let id: String
    let epicKey: String?
    let label: String?
    let title: String
    var tickets: [Ticket]

    var isNamed: Bool { epicKey != nil || label != nil }
}

struct PlayerPocket {
    let player: Player
    let pocket: WheelPocket
    let weight: Double
}

/// What the last spin produced, from the reveal until the croupier moves on.
struct SpinOutcome: Identifiable {
    enum Phase {
        case free, pending, assigned, failed
    }

    let id = UUID()
    let player: Player
    let ticket: Ticket?
    var phase: Phase
    var error: String?
    let at = Date()
}

struct HeadImage {
    let image: CGImage
    /// The rotation already drawn into `image`.
    let turn: CGFloat
}

struct TableCall: Hashable {
    let main: String
    let sub: String
    let isHot: Bool
}

struct RouletteToast: Equatable {
    let id = UUID()
    let text: String
}

/// The ball and the turning head, published every frame of a spin. Kept apart from `RouletteModel` so only the
/// wheel redraws at frame rate.
final class WheelMotion: ObservableObject {
    struct Ball: Equatable {
        /// Radians clockwise from three o'clock, on the fixed bowl.
        var angle: CGFloat
        /// Distance from the centre as a fraction of the wheel's radius.
        var radius: CGFloat
        var scale: CGFloat
    }

    @Published var theta: CGFloat = 0
    @Published var ball: Ball?
    @Published var isBallWinning = false
    @Published var isBallLeaving = false
}

/// The table: who plays, what is in the pool, the wheel and its spin. Main queue only; the service's blocking
/// calls run on a global queue and report back here.
final class RouletteModel: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published private(set) var tickets: [Ticket] = []
    @Published var jqlDraft = ""
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var epics: [String: EpicRef?] = [:]
    @Published private(set) var loading: Set<RouletteLoad> = [.players, .pool, .log]
    @Published private(set) var errors: [RouletteLoad: String] = [:]
    @Published private(set) var grouping: PoolGrouping
    @Published private(set) var flipped: Set<String> = []
    @Published private(set) var scope: RouletteScope?
    @Published private(set) var team: String
    @Published private(set) var mode: RouletteMode
    @Published private(set) var tab: RouletteTab
    @Published private(set) var isMuted: Bool
    @Published private(set) var selectedKey: String?
    @Published private(set) var isSpinning = false
    @Published private(set) var isHolding = false
    @Published private(set) var outcome: SpinOutcome?
    @Published var confirmingUndo: String?
    @Published private(set) var pockets: [PlayerPocket] = []
    @Published private(set) var winner: Int?
    @Published private(set) var call = TableCall(main: "Abriendo la mesa", sub: "trayendo jugadores de GitLab", isHot: false)
    @Published private(set) var toast: RouletteToast?
    @Published private(set) var confetti: ConfettiBurst?
    @Published private(set) var bowlImage: CGImage?
    @Published private(set) var head: HeadImage?
    /// The wheel's frame in window coordinates, where the confetti flies from.
    var wheelFrame: CGRect = .zero

    let motion = WheelMotion()
    let jiraSite: String
    private let service: RouletteService
    private let sound = RouletteSound()
    private let preferences = UserDefaults.standard
    private var wheelPixels = 0
    private var spin: SpinRun?
    private var spinTimer: Timer?

    private static let highPriorities: Set<String> = ["Highest", "High", "Critical", "Blocker"]
    private static let everyone = "todos"
    private static let logLimit = 300

    init(service: RouletteService, jiraSite: String) {
        self.service = service
        self.jiraSite = jiraSite
        grouping = PoolGrouping(rawValue: preferences.string(forKey: "ruleta.group") ?? "") ?? .list
        team = preferences.string(forKey: "ruleta.team") ?? Self.everyone
        mode = RouletteMode(rawValue: preferences.string(forKey: "ruleta.mode") ?? "") ?? .even
        tab = RouletteTab(rawValue: preferences.string(forKey: "ruleta.tab") ?? "") ?? .pool
        isMuted = preferences.bool(forKey: "ruleta.muted")
        sound.isMuted = isMuted
    }

    func reload() {
        guard !isSpinning, !isHolding else { return }
        loadPlayers()
        loadPool()
        loadLog()
    }

    func loadPlayers() {
        load(.players, fetch: { try self.service.players() }) { self.players = $0 }
    }

    func loadPool() {
        load(.pool, fetch: { try self.service.pool() }) { pool in
            self.tickets = pool.tickets
            self.jqlDraft = pool.jql
        } then: { self.loadEpics() }
    }

    func searchPool() {
        let jql = jqlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jql.isEmpty else { return }
        load(.pool, fetch: { try self.service.replacePoolJQL(with: jql) }) { self.tickets = $0 } then: { self.loadEpics() }
    }

    private func loadEpics() {
        guard errors[.pool] == nil, !tickets.isEmpty else { return }
        let keys = tickets.map(\.key)
        load(.epics, fetch: { try self.service.epics(of: keys) }) { self.epics.merge($0) { _, new in new } }
    }

    private func loadLog() {
        load(.log, fetch: { self.service.snapshot.assignments }) { self.assignments = $0 }
    }

    private func load<Value>(_ kind: RouletteLoad, fetch: @escaping () throws -> Value,
                             apply: @escaping (Value) -> Void, then next: (() -> Void)? = nil) {
        loading.insert(kind)
        errors[kind] = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try fetch() }
            DispatchQueue.main.async {
                switch result {
                case .success(let value): apply(value)
                case .failure(let error): self.errors[kind] = error.localizedDescription
                }
                self.loading.remove(kind)
                if kind == .players, !self.teams.contains(self.team) { self.team = Self.everyone }
                self.ensureSelected()
                if kind == .players { self.refreshWheel() }
                self.updateIdleCall()
                next?()
            }
        }
    }

    var teams: [String] {
        [Self.everyone] + Set(players.flatMap(\.teams)).sorted()
    }

    func playableCount(in team: String) -> Int {
        players.filter { $0.canPlay && Self.plays($0, in: team) }.count
    }

    func choose(team: String) {
        guard !isSpinning else { return }
        self.team = team
        preferences.set(team, forKey: "ruleta.team")
        refreshWheel()
    }

    func choose(mode: RouletteMode) {
        guard !isSpinning else { return }
        self.mode = mode
        preferences.set(mode.rawValue, forKey: "ruleta.mode")
        refreshWheel()
    }

    func choose(tab: RouletteTab) {
        self.tab = tab
        preferences.set(tab.rawValue, forKey: "ruleta.tab")
    }

    func choose(grouping: PoolGrouping) {
        self.grouping = grouping
        preferences.set(grouping.rawValue, forKey: "ruleta.group")
    }

    func toggleMute() {
        isMuted.toggle()
        preferences.set(isMuted, forKey: "ruleta.muted")
        sound.isMuted = isMuted
        if !isMuted { sound.prepare() }
    }

    func toggleActive(_ player: Player) {
        let isActive = !player.isActive
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.service.setActive(player.username, isActive) }
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self.show(toast: "No pude guardar: \(error.localizedDescription)")
                    return
                }
                if let index = self.players.firstIndex(where: { $0.username == player.username }) {
                    self.players[index].isActive = isActive
                }
                self.refreshWheel()
            }
        }
    }

    func setWheelPixels(_ pixels: Int) {
        guard pixels > 0, pixels != wheelPixels else { return }
        wheelPixels = pixels
        bowlImage = WheelRenderer.bowl(pixels: pixels)
        redrawHead()
    }

    private func refreshWheel() {
        if isHolding { release() }
        rebuildWheel()
        updateIdleCall()
    }

    private func rebuildWheel() {
        guard !isSpinning, !isHolding else { return }
        pockets = buildPockets()
        winner = nil
        redrawHead()
    }

    /// A turning head is drawn upright and rotated as a layer; one at rest is drawn already turned.
    private func redrawHead() {
        guard wheelPixels > 0 else { return }
        let turn = isSpinning ? 0 : motion.theta
        head = WheelRenderer.head(pixels: wheelPixels, pockets: pockets.map(\.pocket), highlighted: winner, turn: turn)
            .map { HeadImage(image: $0, turn: turn) }
    }

    /// Everyone gets the same slice, or in weighted mode a slice that shrinks with the tickets they already hold.
    private func buildPockets() -> [PlayerPocket] {
        let seated = players.filter { $0.canPlay && Self.plays($0, in: team) }
            .sorted { $0.name.compare($1.name, locale: Locale(identifier: "es")) == .orderedAscending }
        guard !seated.isEmpty else { return [] }
        var firstNames: [String: Int] = [:]
        for player in seated {
            firstNames[Self.nameParts(player).first ?? "", default: 0] += 1
        }
        let weights = seated.map { mode == .weighted ? 1 / Double(1 + $0.openLoad) : 1 }
        let total = weights.reduce(0, +)
        var start = -CGFloat.pi / 2
        return zip(seated, weights).enumerated().map { index, entry in
            let (player, weight) = entry
            let parts = Self.nameParts(player)
            let first = parts.first ?? player.username
            let label = (firstNames[first] ?? 0) > 1 && parts.count > 1 ? "\(first) \(parts[parts.count - 1].prefix(1))." : first
            let span = CGFloat.tau * CGFloat(weight / total)
            let paint: WheelPocket.Paint = seated.count > 1 && seated.count % 2 == 1 && index == seated.count - 1
                ? .verde : index % 2 == 1 ? .negro : .rojo
            defer { start += span }
            return PlayerPocket(player: player, pocket: WheelPocket(label: label, start: start, end: start + span, paint: paint),
                                weight: weight)
        }
    }

    private func pocketIndex(at angle: CGFloat) -> Int {
        guard let first = pockets.first?.pocket.start else { return 0 }
        let normalized = ((angle - first).truncatingRemainder(dividingBy: .tau) + .tau).truncatingRemainder(dividingBy: .tau) + first
        return pockets.firstIndex { normalized >= $0.pocket.start && normalized < $0.pocket.end } ?? pockets.count - 1
    }

    var canSpin: Bool {
        !isSpinning && !loading.contains(.players) && !pockets.isEmpty
    }

    func spinWheel() {
        guard !isSpinning, !loading.contains(.players) else { return }
        if isHolding { release() }
        rebuildWheel()
        guard !pockets.isEmpty else { return }
        sound.prepare()

        let totalWeight = pockets.reduce(0) { $0 + $1.weight }
        var remainder = Self.random() * totalWeight
        var winnerIndex = 0
        while winnerIndex < pockets.count - 1 {
            remainder -= pockets[winnerIndex].weight
            if remainder < 0 { break }
            winnerIndex += 1
        }
        let pick = pockets[winnerIndex]
        let span = pick.pocket.end - pick.pocket.start
        let restingAngle = (pick.pocket.start + pick.pocket.end) / 2 + CGFloat(Self.random() - 0.5) * 0.35 * span

        let ticket = tickets.first { $0.key == selectedKey }
        let pending = ticket.map { assignInBackground($0, to: pick.player) }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        spin = SpinRun(startedAt: CACurrentMediaTime(), reduceMotion: reduceMotion,
                       duration: reduceMotion ? 1.3 : 7.4, ballDuration: reduceMotion ? 1.0 : 5.4,
                       startTheta: motion.theta,
                       turn: reduceMotion ? .tau * 0.15 : .tau * (1.35 + CGFloat(Self.random()) * 0.5),
                       travel: reduceMotion ? .tau * 0.6 : .tau * (4 + CGFloat(Self.random()) * 1.2),
                       restingAngle: restingAngle, winnerIndex: winnerIndex, player: pick.player,
                       ticket: ticket, assignment: pending)

        isSpinning = true
        winner = nil
        motion.isBallWinning = false
        motion.isBallLeaving = false
        setCall("Bola en juego", ticket.map { "\($0.key) en juego" } ?? "tirada libre")
        sound.startRoll()

        advanceSpin()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.advanceSpin() }
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    /// One frame of the spin: the head eases to a stop while the ball runs the other way, drops off the
    /// track, bounces across a few pockets and settles in the winner's.
    private func advanceSpin() {
        guard var run = spin else { return }
        let elapsed = CACurrentMediaTime() - run.startedAt
        let headProgress = min(1, elapsed / run.duration)
        motion.theta = run.startTheta + run.turn * Self.easeOut(headProgress)

        let ballProgress = min(1, elapsed / run.ballDuration)
        var angle = run.restingAngle + run.travel * (1 - Self.easeOut(ballProgress))
        var radius = WheelGeometry.track, scale: CGFloat = 1
        if run.reduceMotion {
            radius = WheelGeometry.track + (WheelGeometry.rest - WheelGeometry.track) * Self.easeOut(ballProgress)
        } else {
            let settling = max(0, (ballProgress - 0.6) / 0.4)
            sound.rollPitch(1 - ballProgress)
            if settling > 0 {
                sound.stopRoll()
                let bounce = pow(1 - settling, 1.5) * abs(cos(settling * .pi * 3))
                radius = WheelGeometry.rest + (WheelGeometry.track - WheelGeometry.rest) * CGFloat(bounce)
                scale = 1 + (settling > 1.0 / 6 ? 0.32 * CGFloat(bounce) : 0)
                angle += 0.24 * CGFloat(pow(1 - settling, 2) * sin(settling * .pi * 5))
                if run.previousBounce > 0.05, bounce <= 0.05 { sound.click(volume: 0.32, frequency: 1700) }
                run.previousBounce = bounce
                let pocket = pocketIndex(at: angle)
                if let last = run.lastPocket, last != pocket { sound.click(volume: 0.12, frequency: 3200) }
                run.lastPocket = pocket
            }
        }
        if ballProgress >= 1 {
            angle = run.restingAngle
            radius = WheelGeometry.rest
            scale = 1
        }
        motion.ball = WheelMotion.Ball(angle: motion.theta + angle, radius: radius, scale: scale)

        if !run.hasCalledNoMoreBets, ballProgress >= 0.45 {
            run.hasCalledNoMoreBets = true
            setCall("No va más", "la bola busca casillero")
        }
        if !run.hasLanded, ballProgress >= 1 {
            run.hasLanded = true
            sound.stopRoll()
            sound.click(volume: 0.4, frequency: 1400)
            winner = run.winnerIndex
            redrawHead()
            motion.isBallWinning = true
        }
        if !run.hasRevealed, elapsed >= run.ballDuration + 0.45 {
            run.hasRevealed = true
            reveal(run.player, ticket: run.ticket, assignment: run.assignment)
        }
        spin = run
        guard headProgress >= 1 else { return }

        spinTimer?.invalidate()
        spinTimer = nil
        spin = nil
        isSpinning = false
        isHolding = true
        motion.theta = motion.theta.truncatingRemainder(dividingBy: .tau)
        motion.ball = WheelMotion.Ball(angle: motion.theta + run.restingAngle, radius: WheelGeometry.rest, scale: 1)
        redrawHead()
    }

    private func assignInBackground(_ ticket: Ticket, to player: Player) -> PendingAssignment {
        let pending = PendingAssignment()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.service.assign(ticket.key, to: player.username) }
            DispatchQueue.main.async { pending.resolve(result) }
        }
        return pending
    }

    private func reveal(_ player: Player, ticket: Ticket?, assignment: PendingAssignment?) {
        let revealed = SpinOutcome(player: player, ticket: ticket, phase: ticket == nil ? .free : .pending)
        outcome = revealed
        setCall(player.name, ticket.map { "se lleva \($0.key)" } ?? "tirada libre", isHot: true)
        announce(ticket.map { "\(player.name) se lleva \($0.key)" } ?? "Sale \(player.name)")
        launchConfetti()
        guard let assignment, let ticket else { return }
        assignment.whenResolved { result in
            switch result {
            case .failure(let error):
                self.updateOutcome(revealed.id) {
                    $0.phase = .failed
                    $0.error = error.localizedDescription
                }
            case .success(let entry):
                self.updateOutcome(revealed.id) { $0.phase = .assigned }
                self.tickets.removeAll { $0.key == ticket.key }
                self.assignments.insert(entry, at: 0)
                if let index = self.players.firstIndex(where: { $0.username == player.username }) {
                    self.players[index].openLoad += 1
                }
                if self.selectedKey == ticket.key { self.selectedKey = nil }
                self.ensureSelected()
            }
        }
    }

    private func updateOutcome(_ id: UUID, _ change: (inout SpinOutcome) -> Void) {
        guard var current = outcome, current.id == id else { return }
        change(&current)
        outcome = current
    }

    /// Clears the ball and the result and puts the wheel back for the next ticket.
    func release() {
        guard isHolding else { return }
        isHolding = false
        outcome = nil
        motion.isBallWinning = false
        motion.isBallLeaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard !self.isSpinning, !self.isHolding else { return }
            self.motion.ball = nil
            self.motion.isBallLeaving = false
        }
        ensureSelected()
        rebuildWheel()
        updateIdleCall()
    }

    func undoLast() {
        guard let outcome, outcome.phase == .assigned, let ticket = outcome.ticket else { return }
        unassign(ticket.key, ticket: ticket) { isUndone in
            guard isUndone else { return }
            self.selectedKey = ticket.key
            self.release()
        }
    }

    func unassign(_ key: String, ticket: Ticket? = nil, then finish: @escaping (Bool) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.service.unassign(key) }
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self.show(toast: "No pude desasignar \(key): \(error.localizedDescription)")
                    finish(false)
                    return
                }
                if let entry = self.assignments.first(where: { $0.key == key }) {
                    self.assignments.removeAll { $0.key == key }
                    if let index = self.players.firstIndex(where: { $0.username == entry.username }), self.players[index].openLoad > 0 {
                        self.players[index].openLoad -= 1
                    }
                    if !self.tickets.contains(where: { $0.key == key }) {
                        self.tickets.insert(ticket ?? Self.placeholder(for: entry), at: 0)
                    }
                    if self.epics[key] == nil { self.loadEpics() }
                }
                self.show(toast: "\(key) volvió al pozo y quedó sin asignar en Jira")
                self.ensureSelected()
                finish(true)
            }
        }
    }

    var remainingInScope: Int {
        tickets.filter(isInScope).count
    }

    var selectedTicket: Ticket? {
        tickets.first { $0.key == selectedKey }
    }

    func select(_ ticket: Ticket) {
        guard !isSpinning else { return }
        selectedKey = ticket.key
        if !isInScope(ticket) { scope = nil }
        if isHolding { release() }
    }

    func play(_ group: PoolGroup) {
        guard !isSpinning else { return }
        let isPlaying = scope?.id == group.id
        let title = group.epicKey.map { "\($0) · \(group.title)" } ?? group.title
        scope = isPlaying ? nil : RouletteScope(grouping: grouping, id: group.id, title: title)
        if isHolding { release() }
        ensureSelected()
    }

    func clearScope() {
        guard !isSpinning else { return }
        scope = nil
        if isHolding { release() }
        ensureSelected()
    }

    func toggle(_ group: PoolGroup) {
        if flipped.contains(group.id) {
            flipped.remove(group.id)
        } else {
            flipped.insert(group.id)
        }
    }

    /// Epic groups start open and tag groups closed; a click flips either.
    func isOpen(_ group: PoolGroup) -> Bool {
        (grouping == .epic) != flipped.contains(group.id)
    }

    func epic(of ticket: Ticket) -> EpicRef? {
        epics[ticket.key] ?? nil
    }

    func isHighPriority(_ ticket: Ticket) -> Bool {
        ticket.priority.map(Self.highPriorities.contains) ?? false
    }

    /// Named groups first, the biggest tags leading; a ticket with several tags shows under each.
    var poolGroups: [PoolGroup] {
        var collected: [PoolGroup] = []
        var positions: [String: Int] = [:]
        for ticket in tickets {
            for group in groups(of: ticket, by: grouping) {
                if let position = positions[group.id] {
                    collected[position].tickets.append(ticket)
                } else {
                    positions[group.id] = collected.count
                    collected.append(PoolGroup(id: group.id, epicKey: group.epicKey, label: group.label, title: group.title,
                                               tickets: [ticket]))
                }
            }
        }
        var named = collected.filter(\.isNamed)
        if grouping == .tag {
            named.sort {
                $0.tickets.count != $1.tickets.count
                    ? $0.tickets.count > $1.tickets.count
                    : $0.title.compare($1.title, locale: Locale(identifier: "es")) == .orderedAscending
            }
        }
        return named + collected.filter { !$0.isNamed }
    }

    private func groups(of ticket: Ticket, by grouping: PoolGrouping) -> [PoolGroup] {
        switch grouping {
        case .epic:
            guard let epic = epic(of: ticket) else {
                return [PoolGroup(id: "epica:", epicKey: nil, label: nil, title: "Sin épica", tickets: [])]
            }
            return [PoolGroup(id: "epica:\(epic.key)", epicKey: epic.key, label: nil,
                              title: epic.summary.isEmpty ? epic.key : epic.summary, tickets: [])]
        case .tag, .list:
            guard !ticket.labels.isEmpty else {
                return [PoolGroup(id: "tag:", epicKey: nil, label: nil, title: "Sin tag", tickets: [])]
            }
            return ticket.labels.map { PoolGroup(id: "tag:\($0)", epicKey: nil, label: $0, title: $0, tickets: []) }
        }
    }

    private func isInScope(_ ticket: Ticket) -> Bool {
        guard let scope else { return true }
        return groups(of: ticket, by: scope.grouping).contains { $0.id == scope.id }
    }

    /// Keeps a ticket in play: the chosen one while it is still in the pool and in scope, else the first that is.
    private func ensureSelected() {
        if let scope, !isSpinning, !isHolding, !tickets.contains(where: isInScope) {
            show(toast: "No quedan tickets en \(scope.title): vuelve todo el pozo")
            self.scope = nil
        }
        if tickets.contains(where: { $0.key == selectedKey && isInScope($0) }) { return }
        selectedKey = tickets.first(where: isInScope)?.key
    }

    var recentAssignments: [Assignment] {
        Array(assignments.prefix(Self.logLimit))
    }

    var hasAssignmentsToday: Bool {
        assignments.contains { Calendar.current.isDateInToday($0.date) }
    }

    func copyToday() {
        let lines = assignments.filter { Calendar.current.isDateInToday($0.date) }.reversed()
            .map { "\($0.key) \($0.summary) → \($0.name)" }
        guard !lines.isEmpty else { return }
        copy(lines.joined(separator: "\n"))
    }

    func copyText(of outcome: SpinOutcome) {
        guard let ticket = outcome.ticket else { return }
        copy("\(ticket.key) \(ticket.summary) → \(outcome.player.name)")
    }

    func copyImage(of outcome: SpinOutcome) {
        let card = ResultCard(outcome: outcome, theta: motion.theta, ball: motion.ball,
                              pockets: pockets.map(\.pocket), winner: winner)
        guard let png = card.png() else {
            show(toast: "No pude generar la imagen")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setData(png, forType: .png) {
            show(toast: "Imagen copiada: pegala en el chat")
            return
        }
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let file = downloads.appendingPathComponent("ruleta-\(outcome.ticket?.key ?? "tirada").png")
        do {
            try png.write(to: file)
            show(toast: "No pude copiar al portapapeles: la guardé en \(file.path)")
        } catch {
            show(toast: "No pude copiar ni guardar la imagen: \(error.localizedDescription)")
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        show(toast: pasteboard.setString(text, forType: .string) ? "Copiado" : "No pude copiar al portapapeles")
    }

    enum Status {
        case loading
        case ready
        case failed(title: String, detail: String)
    }

    var status: Status {
        if loading.contains(.players) || loading.contains(.pool) { return .loading }
        if let poolError = errors[.pool] { return .failed(title: "Jira con error", detail: poolError) }
        if let playersError = errors[.players] { return .failed(title: "GitLab con error", detail: playersError) }
        return .ready
    }

    func browseURL(for key: String) -> URL? {
        URL(string: "https://\(jiraSite)/browse/\(key)")
    }

    func show(toast text: String) {
        let shown = RouletteToast(text: text)
        toast = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if self.toast == shown { self.toast = nil }
        }
    }

    private func updateIdleCall() {
        guard !isSpinning, !isHolding else { return }
        let idle: (String, String)
        if loading.contains(.players) {
            idle = ("Abriendo la mesa", "trayendo jugadores de GitLab")
        } else if errors[.players] != nil {
            idle = ("Mesa cerrada", "no pude armar los jugadores")
        } else if players.isEmpty {
            idle = ("Mesa vacía", "no hay integrantes en los equipos de GitLab")
        } else if pockets.isEmpty {
            idle = ("Nadie de \(team)", "elegí otro equipo o sentá a alguien")
        } else {
            let odds = mode == .weighted ? "compensada por carga abierta" : "chances parejas"
            idle = ("Hagan juego", "\(pockets.count) en la mesa · \(odds)")
        }
        setCall(idle.0, idle.1)
    }

    private func setCall(_ main: String, _ sub: String, isHot: Bool = false) {
        call = TableCall(main: main, sub: sub, isHot: isHot)
    }

    private func announce(_ text: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func launchConfetti() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, wheelFrame.width > 0 else { return }
        let burst = ConfettiBurst(around: wheelFrame)
        confetti = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + ConfettiBurst.duration + 0.1) {
            if self.confetti?.id == burst.id { self.confetti = nil }
        }
    }

    private static func plays(_ player: Player, in team: String) -> Bool {
        team == everyone || player.teams.contains(team)
    }

    private static func nameParts(_ player: Player) -> [String] {
        player.name.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// SystemRandomNumberGenerator draws from the kernel's CSPRNG, as crypto.getRandomValues did.
    private static func random() -> Double {
        var generator = SystemRandomNumberGenerator()
        return Double.random(in: 0..<1, using: &generator)
    }

    private static func easeOut(_ progress: Double) -> CGFloat {
        CGFloat(1 - pow(1 - progress, 3))
    }

    /// What the pool shows for a ticket handed back from the log, before the next search reads it again.
    private static func placeholder(for entry: Assignment) -> Ticket {
        Ticket(key: entry.key, summary: entry.summary, type: "", isSubtask: false,
               status: TicketStatus(name: "", category: .toDo), assignee: nil, priority: nil, labels: [])
    }
}

private struct SpinRun {
    let startedAt: CFTimeInterval
    let reduceMotion: Bool
    let duration: Double
    let ballDuration: Double
    let startTheta: CGFloat
    let turn: CGFloat
    let travel: CGFloat
    let restingAngle: CGFloat
    let winnerIndex: Int
    let player: Player
    let ticket: Ticket?
    let assignment: PendingAssignment?
    var lastPocket: Int?
    var previousBounce = 1.0
    var hasCalledNoMoreBets = false
    var hasLanded = false
    var hasRevealed = false
}

/// The Jira assignment started when the ball is thrown, read when the result is revealed. Main queue only.
private final class PendingAssignment {
    private var result: Result<Assignment, Error>?
    private var waiter: ((Result<Assignment, Error>) -> Void)?

    func resolve(_ result: Result<Assignment, Error>) {
        if let waiter {
            waiter(result)
        } else {
            self.result = result
        }
    }

    func whenResolved(_ waiter: @escaping (Result<Assignment, Error>) -> Void) {
        if let result {
            waiter(result)
        } else {
            self.waiter = waiter
        }
    }
}
