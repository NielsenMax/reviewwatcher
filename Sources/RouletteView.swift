import SwiftUI

struct RouletteView: View {
    @ObservedObject var model: RouletteModel

    private static let maxWheel: CGFloat = 540
    /// Height the stage spends around the wheel: chips, the call, the dock and the gaps between them.
    private static let stageChrome: CGFloat = 330

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - 40
            let stageWidth = (contentWidth - 28) / 2.3
            let wheelSize = max(240, min(stageWidth, Self.maxWheel, geometry.size.height - 110 - Self.stageChrome))
            ZStack(alignment: .bottom) {
                FeltBackground()
                VStack(alignment: .leading, spacing: 22) {
                    RouletteHeader(model: model)
                    HStack(alignment: .top, spacing: 28) {
                        RouletteStage(model: model, wheelSize: wheelSize)
                            .frame(width: stageWidth)
                        RoulettePanel(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 8)
                ConfettiLayer(burst: model.confetti)
                    .ignoresSafeArea()
                ToastBanner(toast: model.toast)
                    .padding(.bottom, 18)
            }
        }
        .foregroundStyle(Casino.ivory.color())
        .environment(\.colorScheme, .dark)
    }
}

private struct RouletteHeader: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Jira + GitLab")
                (Text("Ruleta de ") + Text("Tickets").foregroundColor(Casino.brass.color()))
                    .font(Casino.display(46))
            }
            Spacer()
            StatusPill(status: model.status)
            Button(action: model.toggleMute) {
                HStack(spacing: 6) {
                    Image(systemName: model.isMuted ? "speaker.slash" : "speaker.wave.2")
                    Text("Sonido")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Casino.chalk.color())
                .frame(height: 34)
                .padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Casino.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isMuted ? "Prender el sonido" : "Apagar el sonido")
        }
    }
}

private struct RouletteStage: View {
    @ObservedObject var model: RouletteModel
    let wheelSize: CGFloat

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                FlowLayout(spacing: 6) {
                    ForEach(model.teams, id: \.self) { team in
                        Button { model.choose(team: team) } label: {
                            HStack(spacing: 6) {
                                Text(team == "todos" ? "Todos" : team)
                                Text(String(model.playableCount(in: team)))
                                    .font(Casino.mono(11))
                                    .opacity(0.7)
                            }
                        }
                        .buttonStyle(ChipButtonStyle(isOn: model.team == team))
                        .disabled(model.isSpinning)
                    }
                }
                PillPicker(options: [
                    PillOption(value: RouletteMode.even, title: "Pareja", help: "Todos tienen el mismo casillero"),
                    PillOption(value: RouletteMode.weighted, title: "Compensada",
                               help: "Casillero más grande para quien tiene menos tickets abiertos"),
                ], selection: model.mode, choose: model.choose(mode:))
                .disabled(model.isSpinning)
                .fixedSize()
            }
            CallBanner(call: model.call)
            WheelView(model: model, size: wheelSize)
            RouletteDock(model: model)
                .frame(maxWidth: 540)
        }
    }
}

private struct CallBanner: View {
    let call: TableCall

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Text(call.main)
                    .font(Casino.display(48))
                    .foregroundStyle(call.isHot ? Casino.brass.color() : Casino.ivory.color())
                    .shadow(color: call.isHot ? Casino.brass.color(opacity: 0.35) : .clear, radius: 14)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(call.sub.uppercased())
                    .font(Casino.mono(12))
                    .tracking(1.7)
                    .foregroundStyle(Casino.chalk.color())
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)
            .id(call)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .identity))
        }
        .frame(maxWidth: .infinity, minHeight: 86)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55), value: call)
    }
}

private struct WheelView: View {
    @ObservedObject var model: RouletteModel
    let size: CGFloat

    var body: some View {
        ZStack {
            if let bowl = model.bowlImage {
                Image(decorative: bowl, scale: 1).resizable().interpolation(.high)
            }
            WheelHead(motion: model.motion, head: model.head)
            WheelBall(motion: model.motion, wheelSize: size)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Casino.woodDeep.color()).shadow(color: .black.opacity(0.65), radius: 30, y: 28))
        .background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { model.wheelFrame = frame }
                .onChange(of: frame) { model.wheelFrame = $0 }
        })
        .onAppear { model.setWheelPixels(Self.pixels(for: size)) }
        // macOS 13's onChange runs the closure of the view before the change, so the size comes from its argument.
        .onChange(of: size) { model.setWheelPixels(Self.pixels(for: $0)) }
        .accessibilityElement()
        .accessibilityLabel("Ruleta con los jugadores en la mesa")
    }

    /// Twice the point size on every screen: Retina shows it as is, and on a 1x display the downscale smooths
    /// the edges a rotated bitmap would otherwise step.
    private static func pixels(for size: CGFloat) -> Int {
        Int((size * 2).rounded())
    }
}

private struct WheelHead: View {
    @ObservedObject var motion: WheelMotion
    let head: HeadImage?

    var body: some View {
        if let head {
            Image(decorative: head.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .rotationEffect(.radians(motion.theta - head.turn))
        }
    }
}

private struct WheelBall: View {
    @ObservedObject var motion: WheelMotion
    let wheelSize: CGFloat

    var body: some View {
        if let ball = motion.ball {
            let radius = wheelSize / 2
            BallFace(diameter: max(10, wheelSize * 0.034), isWinning: motion.isBallWinning)
                .scaleEffect(ball.scale)
                .position(x: radius + cos(ball.angle) * ball.radius * radius,
                          y: radius + sin(ball.angle) * ball.radius * radius)
                .opacity(motion.isBallLeaving ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: motion.isBallLeaving)
                .allowsHitTesting(false)
        }
    }
}

private struct BallFace: View {
    let diameter: CGFloat
    let isWinning: Bool

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: .white, location: 0.12),
                .init(color: Casino.ivory.color(), location: 0.4),
                .init(color: RGB(0xB3A785).color(), location: 1),
            ], center: UnitPoint(x: 0.34, y: 0.3), startRadius: 0, endRadius: diameter * 0.75))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            .overlay {
                if isWinning {
                    TimelineView(.animation) { timeline in
                        let glow = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 1.1) + 1) / 2
                        Circle()
                            .strokeBorder(Casino.brass.color(), lineWidth: 2)
                            .shadow(color: Casino.brass.color(opacity: 0.5 + 0.35 * glow), radius: 4 + 7 * glow)
                    }
                    .frame(width: diameter + 4, height: diameter + 4)
                }
            }
    }
}

private struct RouletteDock: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        ZStack {
            if let outcome = model.outcome, model.isHolding || model.isSpinning {
                ResultDock(model: model, outcome: outcome)
                    .id(outcome.id)
                    .transition(.opacity.combined(with: .offset(y: 14)))
            } else {
                IdleDock(model: model)
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: model.outcome?.id)
    }
}

private struct IdleDock: View {
    @ObservedObject var model: RouletteModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: model.selectedTicket == nil ? "Tirada libre" : "En juego")
                if let scope = model.scope {
                    HStack(spacing: 8) {
                        TableTag(text: scope.title, tone: .epic).help(scope.title)
                        Text("quedan \(model.remainingInScope)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Casino.chalk.color())
                            .fixedSize()
                        Button(action: model.clearScope) {
                            Text("×").font(.system(size: 15)).foregroundStyle(Casino.chalk.color())
                        }
                        .buttonStyle(.plain)
                        .help("Volver a sortear todo el pozo")
                        .disabled(model.isSpinning)
                    }
                }
                if let ticket = model.selectedTicket {
                    TicketLine(ticket: ticket, url: model.browseURL(for: ticket.key))
                } else {
                    Text(emptyPoolNote)
                        .foregroundStyle(Casino.chalk.color())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SpinButton(isSpinning: model.isSpinning, action: model.spinWheel)
                .disabled(!model.canSpin)
                .accessibilityLabel("Girar la ruleta")
        }
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Casino.panel))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Casino.line))
    }

    private var emptyPoolNote: String {
        if model.loading.contains(.pool) { return "Buscando en Jira…" }
        if model.errors[.pool] != nil { return "El pozo no cargó: mirá el error en la pestaña Pozo." }
        return "Pozo vacío: sale un nombre y no se asigna."
    }
}

private struct ResultDock: View {
    @ObservedObject var model: RouletteModel
    let outcome: SpinOutcome
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: phaseTitle)
                Text(outcome.player.name)
                    .font(Casino.display(32))
                    .foregroundStyle(Casino.brass.color())
                if let ticket = outcome.ticket {
                    TicketLine(ticket: ticket, url: model.browseURL(for: ticket.key))
                }
                if let error = outcome.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Casino.err.color())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FlowLayout(spacing: 8) {
                if outcome.phase == .assigned || outcome.phase == .free {
                    Button("Copiar imagen") { model.copyImage(of: outcome) }
                        .buttonStyle(CasinoButtonStyle())
                }
                if let ticket = outcome.ticket {
                    Button("Abrir en Jira ↗") { model.browseURL(for: ticket.key).map { openURL($0) } }
                        .buttonStyle(CasinoButtonStyle())
                    if outcome.phase == .assigned {
                        Button("Copiar texto") { model.copyText(of: outcome) }
                            .buttonStyle(CasinoButtonStyle())
                        Button("Deshacer", action: model.undoLast)
                            .buttonStyle(CasinoButtonStyle())
                    }
                }
                Button(model.remainingInScope > 0 ? "Siguiente ticket (\(model.remainingInScope))" : "Listo", action: model.release)
                    .buttonStyle(CasinoButtonStyle(kind: .primary))
                    .disabled(model.isSpinning || outcome.phase == .pending)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Casino.panel))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(outcome.phase == .failed ? Casino.err.color(opacity: 0.55) : Casino.brass.color(opacity: 0.5)))
    }

    private var phaseTitle: String {
        switch outcome.phase {
        case .free: return "Tirada libre · no se asigna"
        case .pending: return "Asignando en Jira…"
        case .assigned: return "Asignado en Jira"
        case .failed: return "No se asignó"
        }
    }
}

struct TicketLine: View {
    let ticket: Ticket
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { url.map { openURL($0) } } label: {
                Text(ticket.key)
                    .font(Casino.mono(13, weight: .bold))
                    .foregroundStyle(Casino.brass.color())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Abrir \(ticket.key) en Jira")
            Text(ticket.summary.isEmpty ? "Sin título" : ticket.summary)
                .lineLimit(2)
        }
    }
}

private struct SpinButton: View {
    let isSpinning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isSpinning ? "···" : "Girar")
                .font(Casino.display(23))
        }
        .buttonStyle(SpinButtonStyle(isSpinning: isSpinning))
    }
}

private struct SpinButtonStyle: ButtonStyle {
    let isSpinning: Bool

    func makeBody(configuration: Configuration) -> some View {
        SpinButtonFace(isPressed: configuration.isPressed, isSpinning: isSpinning) { configuration.label }
    }
}

private struct SpinButtonFace<Label: View>: View {
    let isPressed: Bool
    let isSpinning: Bool
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var isEnabled

    private let diameter: CGFloat = 104

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(stops: [
                .init(color: RGB(0xD42A42).color(), location: 0),
                .init(color: Casino.rojo.color(), location: 0.46),
                .init(color: Casino.rojoDeep.color(), location: 0.6),
            ], center: .center, startRadius: 0, endRadius: diameter / 2))
            if isSpinning {
                TimelineView(.animation) { timeline in
                    stripes.rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            } else {
                stripes
            }
            Circle()
                .strokeBorder(Casino.ivory.color(opacity: 0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .padding(21)
            label().foregroundStyle(Casino.ivory.color())
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.7), radius: 12, y: 12)
        .scaleEffect(isPressed ? 0.95 : 1)
        .saturation(isEnabled || isSpinning ? 1 : 0.3)
        .brightness(isEnabled || isSpinning ? 0 : -0.3)
        .animation(.easeOut(duration: 0.18), value: isPressed)
        .contentShape(Circle())
    }

    /// Eight ivory notches around the rim, like the edge of a casino chip.
    private var stripes: some View {
        var stops: [Gradient.Stop] = []
        for notch in 0..<8 {
            let start = Double(notch) * 45 / 360, edge = start + 11.0 / 360, end = start + 45.0 / 360
            stops += [.init(color: Casino.ivory.color(), location: start), .init(color: Casino.ivory.color(), location: edge),
                      .init(color: Casino.rojo.color(), location: edge), .init(color: Casino.rojo.color(), location: end)]
        }
        return Circle()
            .fill(AngularGradient(stops: stops, center: .center, angle: .degrees(-90)))
            .mask(Circle().strokeBorder(Color.black, lineWidth: diameter / 2 * 0.4))
    }
}
