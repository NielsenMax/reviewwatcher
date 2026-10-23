import SwiftUI

/// Lays its children in rows, wrapping to a new row when the next one would not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, within: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, within maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row(y: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > maxWidth {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

struct CasinoButtonStyle: ButtonStyle {
    enum Kind {
        case plain, primary, ghost, danger
    }

    var kind = Kind.plain

    func makeBody(configuration: Configuration) -> some View {
        CasinoButtonFace(kind: kind, isPressed: configuration.isPressed) { configuration.label }
    }
}

private struct CasinoButtonFace<Label: View>: View {
    let kind: CasinoButtonStyle.Kind
    let isPressed: Bool
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label()
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 11).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: kind == .ghost ? [4, 3] : [])))
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.5)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Casino.ink.color()
        case .ghost: return Casino.chalk.color()
        case .plain, .danger: return Casino.ivory.color()
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return Casino.brass.color()
        case .ghost: return .clear
        case .danger: return Casino.rojo.color(opacity: 0.25)
        case .plain: return Casino.ivory.color(opacity: 0.05)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return Casino.brass.color()
        case .danger: return Casino.rojo.color(opacity: 0.7)
        case .plain, .ghost: return Casino.lineStrong
        }
    }
}

struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? Casino.ink.color() : Casino.chalk.color())
            .padding(.vertical, 7)
            .padding(.leading, 13)
            .padding(.trailing, 11)
            .background(Capsule().fill(isOn ? Casino.ivory.color() : .clear))
            .overlay(Capsule().strokeBorder(isOn ? Casino.ivory.color() : Casino.line))
            .contentShape(Capsule())
    }
}

struct PillOption<Value: Hashable> {
    let value: Value
    let title: String
    var help = ""
}

/// The brass-on-dark segmented pill the table uses for modes and groupings.
struct PillPicker<Value: Hashable>: View {
    let options: [PillOption<Value>]
    let selection: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button { choose(option.value) } label: {
                    Text(option.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(option.value == selection ? Casino.ink.color() : Casino.chalk.color())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(option.value == selection ? Casino.brass.color() : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.help)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.22)))
        .overlay(Capsule().strokeBorder(Casino.line))
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Casino.mono(11))
            .tracking(1.76)
            .foregroundStyle(Casino.chalk.color())
    }
}

struct TableTag: View {
    enum Tone {
        case plain, warn, epic
    }

    let text: String
    var tone = Tone.plain

    var body: some View {
        Text(text)
            .font(Casino.mono(10.5))
            .tracking(tone == .epic ? 0.2 : 0.84)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
    }

    private var foreground: Color {
        switch tone {
        case .plain: return Casino.chalk.color()
        case .warn: return Casino.warn.color()
        case .epic: return Casino.ivory.color()
        }
    }

    private var border: Color {
        switch tone {
        case .plain: return Casino.line
        case .warn: return Casino.warn.color(opacity: 0.5)
        case .epic: return Casino.brass.color(opacity: 0.45)
        }
    }
}

struct PriorityTag: View {
    let priority: String
    let isHigh: Bool

    var body: some View {
        Text(priority)
            .font(Casino.mono(10.5))
            .tracking(0.6)
            .foregroundStyle(isHigh ? Casino.ivory.color() : Casino.chalk.color())
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHigh ? Casino.rojo.color(opacity: 0.25) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHigh ? Casino.rojo.color(opacity: 0.7) : Casino.line))
    }
}

struct InPlayBadge: View {
    var body: some View {
        Text("EN JUEGO")
            .font(Casino.mono(10))
            .tracking(1.2)
            .foregroundStyle(Casino.ink.color())
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(Casino.brass.color()))
    }
}

/// The small ↗ that opens something in Jira.
struct JiraLink: View {
    let url: URL?
    let help: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { url.map { openURL($0) } } label: {
            Text("↗")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Casino.chalk.color())
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(url == nil)
    }
}

struct EmptyNote: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(isError ? Casino.err.color() : Casino.chalk.color())
            .multilineTextAlignment(isError ? .leading : .center)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: isError ? .leading : .center)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isError ? Casino.err.color(opacity: 0.5) : Casino.lineStrong,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

struct StatusPill: View {
    let status: RouletteModel.Status

    var body: some View {
        HStack(spacing: 8) {
            dot
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Casino.chalk.color())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Capsule().fill(Casino.panel))
        .overlay(Capsule().strokeBorder(Casino.line))
        .help(detail)
    }

    @ViewBuilder
    private var dot: some View {
        switch status {
        case .loading:
            TimelineView(.animation) { timeline in
                let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi) + 1) / 2
                Circle().fill(Casino.chalk.color()).frame(width: 8, height: 8).opacity(0.3 + 0.7 * phase)
            }
            .frame(width: 8, height: 8)
        case .ready:
            Circle().fill(Casino.ok.color()).frame(width: 8, height: 8)
                .background(Circle().fill(Casino.ok.color(opacity: 0.18)).frame(width: 14, height: 14))
        case .failed:
            Circle().fill(Casino.err.color()).frame(width: 8, height: 8)
        }
    }

    private var title: String {
        switch status {
        case .loading: return "Cargando…"
        case .ready: return "Jira + GitLab"
        case .failed(let title, _): return title
        }
    }

    private var detail: String {
        switch status {
        case .loading: return ""
        case .ready: return "Pozo desde Jira, jugadores desde GitLab."
        case .failed(_, let detail): return detail
        }
    }
}

struct ToastBanner: View {
    let toast: RouletteToast?

    var body: some View {
        ZStack {
            if let toast {
                Text(toast.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Casino.ink.color())
                    .padding(.vertical, 11)
                    .padding(.horizontal, 18)
                    .background(Capsule().fill(Casino.ivory.color()))
                    .shadow(color: .black.opacity(0.6), radius: 15, y: 12)
                    .id(toast.id)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast)
        .allowsHitTesting(false)
    }
}

/// The table's green baize: a lit centre falling off to the edges, under a faint grain.
struct FeltBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(stops: [
                    .init(color: Casino.feltHi.color(), location: 0),
                    .init(color: Casino.felt.color(), location: 0.48),
                    .init(color: Casino.feltDeep.color(), location: 1),
                ], center: UnitPoint(x: 0.32, y: 0.38), startRadius: 0,
                endRadius: max(geometry.size.width, geometry.size.height) * 0.8)
                if let grain = Self.grain {
                    Image(decorative: grain, scale: 1)
                        .resizable(resizingMode: .tile)
                        .opacity(0.15)
                }
            }
        }
        .ignoresSafeArea()
    }

    private static let grain: CGImage? = {
        let side = 180
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index + 3] = UInt8.random(in: 0...140, using: &generator)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}
