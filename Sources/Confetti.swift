import SwiftUI

/// Casino chips thrown up from the wheel when a name comes out.
struct ConfettiBurst: Identifiable {
    struct Chip {
        let x: CGFloat
        let y: CGFloat
        let velocityX: CGFloat
        let velocityY: CGFloat
        let radius: CGFloat
        let flip: CGFloat
        let flipSpeed: CGFloat
        let rotation: CGFloat
        let spin: CGFloat
        let paint: RGB
    }

    static let duration: TimeInterval = 2.4
    private static let chipCount = 54
    /// Points per second squared.
    private static let gravity: CGFloat = 1500
    /// Speed kept per 60 Hz step, as the browser's per-frame damping did.
    private static let drag: CGFloat = 0.992
    private static let step: CGFloat = 1.0 / 60

    let id = UUID()
    let startedAt = Date()
    let chips: [Chip]

    init(around wheel: CGRect) {
        let paints = [Casino.rojo, Casino.negro, Casino.brass, Casino.verde, Casino.rojo, Casino.negro]
        chips = (0..<Self.chipCount).map { _ in
            let angle = -CGFloat.pi / 2 + (Self.random() - 0.5) * .pi * 1.25
            let speed = 420 + Self.random() * 620
            return Chip(x: wheel.midX + (Self.random() - 0.5) * wheel.width * 0.3,
                        y: wheel.midY + (Self.random() - 0.5) * wheel.height * 0.3,
                        velocityX: cos(angle) * speed, velocityY: sin(angle) * speed,
                        radius: max(7, wheel.width * (0.016 + Self.random() * 0.012)),
                        flip: Self.random() * .tau, flipSpeed: 4 + Self.random() * 9,
                        rotation: Self.random() * .tau, spin: (Self.random() - 0.5) * 6,
                        paint: paints[Int(Self.random() * CGFloat(paints.count)) % paints.count])
        }
    }

    /// Replays the flight in fixed steps, so a frame depends only on the time elapsed.
    func draw(in context: inout GraphicsContext, at elapsed: TimeInterval) {
        let life = elapsed / Self.duration
        guard life < 1 else { return }
        context.opacity = life > 0.75 ? max(0, 1 - (life - 0.75) / 0.25) : 1
        let steps = Int(CGFloat(elapsed) / Self.step)
        for chip in chips {
            var x = chip.x, y = chip.y, velocityX = chip.velocityX, velocityY = chip.velocityY
            for _ in 0..<steps {
                velocityY += Self.gravity * Self.step
                velocityX *= Self.drag
                velocityY *= Self.drag
                x += velocityX * Self.step
                y += velocityY * Self.step
            }
            let time = CGFloat(elapsed)
            draw(chip, in: context, at: CGPoint(x: x, y: y), flip: chip.flip + chip.flipSpeed * time,
                 rotation: chip.rotation + chip.spin * time)
        }
    }

    private func draw(_ chip: Chip, in context: GraphicsContext, at center: CGPoint, flip: CGFloat, rotation: CGFloat) {
        var chipContext = context
        chipContext.translateBy(x: center.x, y: center.y)
        chipContext.rotate(by: .radians(rotation))
        chipContext.scaleBy(x: 1, y: max(0.08, abs(cos(flip))))
        let radius = chip.radius
        chipContext.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                         with: .color(chip.paint.color()))
        let outer = radius * 0.78, inner = radius * 0.48
        chipContext.stroke(Path(ellipseIn: CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2)),
                           with: .color(Casino.ivory.color(opacity: 0.92)),
                           style: StrokeStyle(lineWidth: radius * 0.24, dash: [radius * 0.42, radius * 0.36]))
        chipContext.stroke(Path(ellipseIn: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2)),
                           with: .color(Casino.ivory.color(opacity: 0.5)),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.07)))
    }

    private static func random() -> CGFloat {
        var generator = SystemRandomNumberGenerator()
        return CGFloat.random(in: 0..<1, using: &generator)
    }
}

struct ConfettiLayer: View {
    let burst: ConfettiBurst?

    var body: some View {
        if let burst {
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    burst.draw(in: &context, at: timeline.date.timeIntervalSince(burst.startedAt))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
