import AppKit
import CoreText

/// Radii of the wheel's rings, as fractions of its radius.
enum WheelGeometry {
    static let rimOut: CGFloat = 0.995
    static let rimIn: CGFloat = 0.905
    static let track: CGFloat = 0.872
    static let deflect: CGFloat = 0.84
    static let trackIn: CGFloat = 0.815
    static let headOut: CGFloat = 0.8
    static let floor: CGFloat = 0.7
    static let rest: CGFloat = 0.752
    static let headIn: CGFloat = 0.3
}

struct WheelPocket {
    enum Paint {
        case rojo, negro, verde, ghostLight, ghostDark

        var rgb: RGB {
            switch self {
            case .rojo: return Casino.rojo
            case .negro: return Casino.negro
            case .verde: return Casino.verde
            case .ghostLight: return RGB(0x1F3029)
            case .ghostDark: return RGB(0x18251F)
            }
        }
    }

    let label: String
    /// Radians clockwise from three o'clock; the first pocket starts at twelve.
    let start: CGFloat
    let end: CGFloat
    let paint: Paint

    static func ghosts() -> [WheelPocket] {
        let count = 12
        return (0..<count).map { index in
            let start = -CGFloat.pi / 2 + CGFloat(index) * .tau / CGFloat(count)
            return WheelPocket(label: "", start: start, end: start + .tau / CGFloat(count),
                               paint: index.isMultiple(of: 2) ? .ghostLight : .ghostDark)
        }
    }
}

extension CGFloat {
    static let tau = CGFloat.pi * 2
}

/// Paints the wheel the way the Node version's canvas did: the fixed bowl, and the turning head with one
/// pocket per player.
enum WheelRenderer {
    static func bowl(pixels: Int) -> CGImage? {
        Painter.image(pixels: pixels) { context, radius in
            let rimIn = radius * WheelGeometry.rimIn, rimOut = radius * WheelGeometry.rimOut
            let trackIn = radius * WheelGeometry.trackIn
            Painter.fill(context, Painter.annulus(rimIn, rimOut), radial: [
                (0, Casino.woodDeep.cgColor()), (0.3, Casino.woodHi.cgColor()),
                (0.75, Casino.wood.cgColor()), (1, Casino.woodDeep.cgColor()),
            ], from: (.zero, rimIn), to: (.zero, rimOut))

            context.saveGState()
            context.setAlpha(0.14)
            context.setStrokeColor(.black)
            for index in 0..<16 {
                let ringRadius = radius * (WheelGeometry.rimIn + (WheelGeometry.rimOut - WheelGeometry.rimIn) * (CGFloat(index) + 0.5) / 16)
                let start = CGFloat(index) * 0.9
                context.setLineWidth(radius * 0.0018 * CGFloat(1 + index % 3))
                context.addArc(center: .zero, radius: ringRadius, startAngle: start,
                               endAngle: start + .tau * (0.35 + CGFloat(index % 4) * 0.12), clockwise: false)
                context.strokePath()
            }
            context.restoreGState()
            Painter.ring(context, radius: rimOut - radius * 0.004, color: Casino.brassDim.cgColor(), width: radius * 0.008)
            Painter.ring(context, radius: rimIn, color: Casino.brass.cgColor(), width: radius * 0.007)

            Painter.fill(context, Painter.annulus(trackIn, rimIn), radial: [
                (0, Casino.track.cgColor()), (0.65, Casino.trackHi.cgColor()), (1, Casino.track.cgColor()),
            ], from: (.zero, trackIn), to: (.zero, rimIn))
            paintTrackSheen(context, inner: trackIn, outer: rimIn)

            for index in 0..<8 {
                context.saveGState()
                context.rotate(by: CGFloat(index) * .tau / 8 + .tau / 16)
                context.translateBy(x: radius * WheelGeometry.deflect, y: 0)
                if index % 2 == 1 { context.rotate(by: .pi / 2) }
                let width = radius * 0.024, length = radius * 0.055
                let diamond = CGMutablePath()
                diamond.move(to: CGPoint(x: 0, y: -length / 2))
                diamond.addLine(to: CGPoint(x: width / 2, y: 0))
                diamond.addLine(to: CGPoint(x: 0, y: length / 2))
                diamond.addLine(to: CGPoint(x: -width / 2, y: 0))
                diamond.closeSubpath()
                Painter.fill(context, diamond, linear: brassSheen, from: CGPoint(x: -width / 2, y: 0), to: CGPoint(x: width / 2, y: 0))
                context.restoreGState()
            }
            context.setFillColor(Casino.woodDeep.cgColor())
            context.fillEllipse(in: Painter.square(radius: trackIn))
            Painter.ring(context, radius: trackIn, color: CGColor(gray: 0, alpha: 0.55), width: radius * 0.02)
        }
    }

    /// `turn` bakes the head's rotation into the drawing, so names at rest are set at their final angle rather
    /// than resampled by a rotated layer.
    static func head(pixels: Int, pockets: [WheelPocket], highlighted: Int?, turn: CGFloat = 0) -> CGImage? {
        Painter.image(pixels: pixels) { context, radius in
            context.rotate(by: turn)
            let outer = radius * WheelGeometry.headOut, inner = radius * WheelGeometry.headIn
            let floor = radius * WheelGeometry.floor
            let isGhost = pockets.isEmpty
            let shown = isGhost ? WheelPocket.ghosts() : pockets

            context.setFillColor(Casino.woodDeep.cgColor())
            context.fillEllipse(in: Painter.square(radius: outer + radius * 0.014))

            for (index, pocket) in shown.enumerated() {
                let base = pocket.paint.rgb
                let sector = Painter.sector(inner, outer, pocket.start, pocket.end)
                Painter.fill(context, sector, radial: [
                    (0, base.mixed(-0.45).cgColor()), (0.72, base.cgColor()), (1, base.mixed(-0.12).cgColor()),
                ], from: (.zero, inner), to: (.zero, outer))
                if index == highlighted {
                    Painter.fill(context, sector, radial: [
                        (0, Casino.brass.mixed(-0.35).cgColor()), (0.75, Casino.brass.cgColor()),
                        (1, Casino.brass.mixed(0.3).cgColor()),
                    ], from: (.zero, inner), to: (.zero, outer))
                }
                context.addPath(Painter.sector(floor, outer, pocket.start, pocket.end))
                context.setFillColor(CGColor(gray: 0, alpha: index == highlighted ? 0.16 : 0.32))
                context.fillPath()
            }

            context.setLineCap(.round)
            if shown.count > 1 {
                context.setStrokeColor(Casino.brass.cgColor())
                context.setLineWidth(max(1, radius * 0.007))
                for pocket in shown {
                    context.move(to: CGPoint(x: cos(pocket.start) * inner, y: sin(pocket.start) * inner))
                    context.addLine(to: CGPoint(x: cos(pocket.start) * (outer + radius * 0.008),
                                                y: sin(pocket.start) * (outer + radius * 0.008)))
                    context.strokePath()
                }
            }
            Painter.ring(context, radius: floor, color: Casino.brassDim.cgColor(), width: radius * 0.004)
            Painter.ring(context, radius: outer, color: Casino.brass.cgColor(), width: radius * 0.008)

            if !isGhost {
                for (index, pocket) in shown.enumerated() {
                    paintLabel(pocket, isHighlighted: index == highlighted, context: context, radius: radius)
                }
            }
            paintHub(context, radius: radius, inner: inner)
        }
    }

    private static let brassSheen: [(CGFloat, CGColor)] = [
        (0, Casino.brass.mixed(0.4).cgColor()), (0.5, Casino.brass.cgColor()), (1, Casino.brassDim.cgColor()),
    ]

    /// Two soft glints swept around the ball track, standing in for the browser's conic gradient.
    private static func paintTrackSheen(_ context: CGContext, inner: CGFloat, outer: CGFloat) {
        let stops: [(CGFloat, CGFloat)] = [(0, 0), (0.07, 0.12), (0.15, 0), (0.55, 0), (0.61, 0.06), (0.68, 0), (1, 0)]
        let start = -CGFloat.pi * 0.8
        let wedges = 360
        for wedge in 0..<wedges {
            let from = CGFloat(wedge) / CGFloat(wedges), to = CGFloat(wedge + 1) / CGFloat(wedges)
            let alpha = Painter.interpolate(stops, at: (from + to) / 2)
            guard alpha > 0.001 else { continue }
            context.addPath(Painter.sector(inner, outer, start + from * .tau, start + to * .tau + 0.002))
            context.setFillColor(CGColor(gray: 1, alpha: alpha))
            context.fillPath()
        }
    }

    private static func paintLabel(_ pocket: WheelPocket, isHighlighted: Bool, context: CGContext, radius: CGFloat) {
        let span = pocket.end - pocket.start
        var fontSize = min(radius * 0.066, span * radius * 0.21)
        guard fontSize >= radius * 0.02 else { return }
        let room = radius * (WheelGeometry.floor - WheelGeometry.headIn) - radius * 0.07
        var line = Painter.line(pocket.label, font: .systemFont(ofSize: fontSize, weight: .semibold))
        let width = Painter.width(of: line)
        if width > room {
            fontSize *= room / width
            line = Painter.line(pocket.label, font: .systemFont(ofSize: fontSize, weight: .semibold))
        }
        context.saveGState()
        context.rotate(by: (pocket.start + pocket.end) / 2)
        context.setShadow(offset: .zero, blur: isHighlighted ? 0 : radius * 0.012, color: CGColor(gray: 0, alpha: 0.45))
        context.setFillColor((isHighlighted ? Casino.ink : Casino.ivory).cgColor())
        Painter.draw(line, context: context, rightEdge: radius * WheelGeometry.floor - radius * 0.035, middle: 0)
        context.restoreGState()
    }

    private static func paintHub(_ context: CGContext, radius: CGFloat, inner: CGFloat) {
        Painter.fill(context, CGPath(ellipseIn: Painter.square(radius: inner), transform: nil), radial: [
            (0, Casino.woodHi.cgColor()), (0.6, Casino.wood.cgColor()), (1, Casino.woodDeep.cgColor()),
        ], from: (CGPoint(x: -inner * 0.3, y: -inner * 0.3), inner * 0.1), to: (.zero, inner))
        Painter.ring(context, radius: inner, color: Casino.brass.cgColor(), width: radius * 0.008)

        let arm = radius * 0.2, armWidth = radius * 0.03
        for quarter in 0..<4 {
            context.saveGState()
            context.rotate(by: CGFloat(quarter) * .pi / 2 + .pi / 4)
            let bar = CGPath(roundedRect: CGRect(x: 0, y: -armWidth / 2, width: arm, height: armWidth),
                             cornerWidth: armWidth / 2, cornerHeight: armWidth / 2, transform: nil)
            let knob = CGPath(ellipseIn: Painter.square(radius: armWidth * 0.95, center: CGPoint(x: arm, y: 0)), transform: nil)
            for shape in [bar, knob] {
                Painter.fill(context, shape, linear: brassSheen,
                            from: CGPoint(x: 0, y: -armWidth / 2), to: CGPoint(x: 0, y: armWidth / 2))
            }
            context.restoreGState()
        }
        Painter.fill(context, CGPath(ellipseIn: Painter.square(radius: radius * 0.07), transform: nil), radial: [
            (0, Casino.brass.mixed(0.65).cgColor()), (0.5, Casino.brass.cgColor()), (1, Casino.brassDim.cgColor()),
        ], from: (CGPoint(x: -radius * 0.022, y: -radius * 0.026), radius * 0.004), to: (.zero, radius * 0.075))
    }
}

/// Drawing helpers that keep the browser canvas's conventions: y grows downward and angles turn clockwise.
enum Painter {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func image(pixels: Int, draw: (CGContext, CGFloat) -> Void) -> CGImage? {
        guard pixels > 0, let context = bitmap(width: pixels, height: pixels) else { return nil }
        let radius = CGFloat(pixels) / 2
        context.translateBy(x: radius, y: radius)
        draw(context, radius)
        return context.makeImage()
    }

    /// A context flipped so the origin sits top left, as in the browser.
    static func bitmap(width: Int, height: Int) -> CGContext? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        return context
    }

    static func square(radius: CGFloat, center: CGPoint = .zero) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// The two circles run in opposite directions, so the default winding rule leaves the middle empty.
    static func annulus(_ inner: CGFloat, _ outer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: outer, y: 0))
        path.addArc(center: .zero, radius: outer, startAngle: 0, endAngle: .tau, clockwise: false)
        path.closeSubpath()
        path.move(to: CGPoint(x: inner, y: 0))
        path.addArc(center: .zero, radius: inner, startAngle: .tau, endAngle: 0, clockwise: true)
        path.closeSubpath()
        return path
    }

    static func sector(_ inner: CGFloat, _ outer: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: .zero, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    static func ring(_ context: CGContext, radius: CGFloat, color: CGColor, width: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.strokeEllipse(in: square(radius: radius))
    }

    static func fill(_ context: CGContext, _ path: CGPath, radial stops: [(CGFloat, CGColor)],
                     from start: (CGPoint, CGFloat), to end: (CGPoint, CGFloat)) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawRadialGradient(gradient, startCenter: start.0, startRadius: start.1, endCenter: end.0,
                                   endRadius: end.1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    static func fill(_ context: CGContext, _ path: CGPath, linear stops: [(CGFloat, CGColor)],
                     from start: CGPoint, to end: CGPoint) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    static func interpolate(_ stops: [(CGFloat, CGFloat)], at position: CGFloat) -> CGFloat {
        for (lower, upper) in zip(stops, stops.dropFirst()) where position >= lower.0 && position <= upper.0 {
            let share = upper.0 > lower.0 ? (position - lower.0) / (upper.0 - lower.0) : 0
            return lower.1 + (upper.1 - lower.1) * share
        }
        return stops.last?.1 ?? 0
    }

    /// The line takes its colour from the context's fill colour when drawn.
    static func line(_ text: String, font: NSFont, tracking: CGFloat = 0) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: tracking,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func draw(_ line: CTLine, context: CGContext, rightEdge: CGFloat, middle: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.textPosition = CGPoint(x: rightEdge - width, y: middle + (ascent - descent) / 2)
        CTLineDraw(line, context)
    }

    static func draw(_ line: CTLine, context: CGContext, at baseline: CGPoint) {
        context.textPosition = baseline
        CTLineDraw(line, context)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        CGGradient(colorsSpace: colorSpace, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))
    }
}
