import AppKit
import CoreText

/// The 1200×630 picture of a spin's result, made to be pasted in a chat: the wheel as it stopped, the name and
/// the ticket.
struct ResultCard {
    let outcome: SpinOutcome
    let theta: CGFloat
    let ball: WheelMotion.Ball?
    let pockets: [WheelPocket]
    let winner: Int?

    private static let width = 1200
    private static let height = 630
    private static let wheelDiameter: CGFloat = 530
    private static let textLeft: CGFloat = 650

    func png() -> Data? {
        guard let context = Painter.bitmap(width: Self.width, height: Self.height) else { return nil }
        let width = CGFloat(Self.width), height = CGFloat(Self.height)
        Painter.fill(context, CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), radial: [
            (0, Casino.feltHi.cgColor()), (0.5, Casino.felt.cgColor()), (1, Casino.feltDeep.cgColor()),
        ], from: (CGPoint(x: width * 0.28, y: height * 0.45), 40), to: (CGPoint(x: width * 0.28, y: height * 0.45), width * 0.95))
        drawWheel(in: context, center: CGPoint(x: 60 + Self.wheelDiameter / 2, y: height / 2))
        drawText(in: context, height: height, maxWidth: width - Self.textLeft - 60)
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func drawWheel(in context: CGContext, center: CGPoint) {
        let diameter = Self.wheelDiameter
        let pixels = Int(diameter * 2)
        context.saveGState()
        // Shadow offsets ignore the flipped transform, so a drop downward is a negative height.
        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: CGColor(gray: 0, alpha: 0.55))
        context.setFillColor(Casino.woodDeep.cgColor())
        context.fillEllipse(in: Painter.square(radius: diameter / 2 - 2, center: center))
        context.restoreGState()

        let frame = Painter.square(radius: diameter / 2, center: center)
        if let bowl = WheelRenderer.bowl(pixels: pixels) { drawUpright(bowl, in: frame, context: context) }
        if let head = WheelRenderer.head(pixels: pixels, pockets: pockets, highlighted: winner) {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: theta)
            drawUpright(head, in: Painter.square(radius: diameter / 2), context: context)
            context.restoreGState()
        }
        guard let ball else { return }
        let ballRadius = diameter * 0.018
        let ballCenter = CGPoint(x: center.x + cos(ball.angle) * ball.radius * diameter / 2,
                                 y: center.y + sin(ball.angle) * ball.radius * diameter / 2)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 18, color: Casino.brass.cgColor())
        context.setFillColor(Casino.ivory.cgColor())
        context.fillEllipse(in: Painter.square(radius: ballRadius, center: ballCenter))
        context.restoreGState()
        Painter.fill(context, CGPath(ellipseIn: Painter.square(radius: ballRadius, center: ballCenter), transform: nil), radial: [
            (0, CGColor(gray: 1, alpha: 1)), (0.4, Casino.ivory.cgColor()), (1, RGB(0xB3A785).cgColor()),
        ], from: (CGPoint(x: ballCenter.x - ballRadius * 0.3, y: ballCenter.y - ballRadius * 0.4), ballRadius * 0.1),
           to: (ballCenter, ballRadius))
    }

    private func drawText(in context: CGContext, height: CGFloat, maxWidth: CGFloat) {
        let left = Self.textLeft
        var baseline: CGFloat = 150
        context.setFillColor(Casino.chalk.cgColor())
        Painter.draw(Painter.line("RULETA DE TICKETS", font: Casino.monoFont(20), tracking: 4), context: context,
                    at: CGPoint(x: left, y: baseline))

        context.setFillColor(Casino.brass.cgColor())
        for line in Self.wrap(outcome.player.name, font: Casino.displayFont(66), maxWidth: maxWidth, maxLines: 2) {
            baseline += 74
            Painter.draw(line, context: context, at: CGPoint(x: left, y: baseline))
        }

        if let ticket = outcome.ticket {
            baseline += 64
            context.setFillColor(Casino.ivory.cgColor())
            Painter.draw(Painter.line(ticket.key, font: Casino.monoFont(28, weight: .bold)), context: context,
                        at: CGPoint(x: left, y: baseline))
            let summary = ticket.summary.isEmpty ? "Sin título" : ticket.summary
            for line in Self.wrap(summary, font: .systemFont(ofSize: 28, weight: .semibold), maxWidth: maxWidth, maxLines: 4) {
                baseline += 40
                Painter.draw(line, context: context, at: CGPoint(x: left, y: baseline))
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        let footer = "\(outcome.ticket == nil ? "Tirada libre" : "Asignado en Jira") · \(formatter.string(from: outcome.at))"
        context.setFillColor(Casino.chalk.cgColor())
        Painter.draw(Painter.line(footer, font: Casino.monoFont(20)), context: context, at: CGPoint(x: left, y: height - 70))
    }

    /// The bitmap is flipped so y grows downward; images go back upright before they are drawn.
    private func drawUpright(_ image: CGImage, in frame: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()
    }

    /// Breaks on spaces and ellipsizes the last line kept.
    private static func wrap(_ text: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> [CTLine] {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if current.isEmpty || Painter.width(of: Painter.line(candidate, font: font)) <= maxWidth {
                current = candidate
                continue
            }
            lines.append(current)
            current = word
        }
        if !current.isEmpty { lines.append(current) }
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            var last = lines[maxLines - 1]
            while !last.isEmpty, Painter.width(of: Painter.line(last + "…", font: font)) > maxWidth {
                last.removeLast()
            }
            lines[maxLines - 1] = last.trimmingCharacters(in: .whitespaces) + "…"
        }
        return lines.map { Painter.line($0, font: font) }
    }
}
