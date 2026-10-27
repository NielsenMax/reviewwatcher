import AppKit
import SwiftUI

/// The merge celebration laid out for one screen: a gilded bull charges across it, and where it passes the middle a
/// shockwave throws casino chips and rains gold streamers. Every frame is a function of the time elapsed.
struct CelebrationScene {
    struct Art {
        let silhouette: CGImage
        let gold: CGImage
    }

    struct BullPose {
        let center: CGPoint
        let tilt: Angle
    }

    static let duration: TimeInterval = 3.8
    static let impact = chargeStart + chargeSeconds / 2
    private static let chargeStart: TimeInterval = 0.05
    private static let chargeSeconds: TimeInterval = 1.3
    private static let fadeInSeconds: TimeInterval = 0.3
    private static let fadeOutStart: TimeInterval = 3.0
    private static let puffSeconds = 0.8
    private static let ringSeconds = 0.9
    private static let flashSeconds = 0.35

    let size: CGSize
    let art: Art
    let label: String
    let title: String
    let isStill: Bool
    let bullSize: CGSize
    private let groundY: CGFloat
    private let chips: ConfettiBurst
    private let puffs: [Puff]
    private let streaks: [Streak]
    private let streamers: [Streamer]

    init(size: CGSize, art: Art, label: String, title: String, isStill: Bool) {
        self.size = size
        self.art = art
        self.label = label
        self.title = title
        self.isStill = isStill
        let bullHeight = size.height * 0.34
        bullSize = CGSize(width: bullHeight * CGFloat(art.gold.width) / CGFloat(art.gold.height), height: bullHeight)
        groundY = size.height * 0.86
        let impactPoint = CGPoint(x: size.width / 2, y: groundY - bullHeight * 0.55)
        chips = ConfettiBurst(around: CGRect(x: impactPoint.x - size.width * 0.2, y: impactPoint.y - bullHeight * 0.25,
                                             width: size.width * 0.4, height: bullHeight * 0.5))
        puffs = (0..<70).map { _ in Puff() }
        streaks = (0..<26).map { _ in Streak() }
        streamers = (0..<170).map { _ in Streamer(across: size) }
    }

    private var impactPoint: CGPoint {
        CGPoint(x: size.width / 2, y: groundY - bullSize.height * 0.55)
    }

    func visibility(at elapsed: TimeInterval) -> Double {
        let fadeIn = min(1, elapsed / Self.fadeInSeconds)
        let fadeOut = 1 - min(1, max(0, (elapsed - Self.fadeOutStart) / (Self.duration - Self.fadeOutStart)))
        return max(0, fadeIn * fadeOut)
    }

    /// Where the bull stands `lag` frames of its own trail behind the present, or nil while it is off the stage.
    func bullPose(at elapsed: TimeInterval, lag: Int = 0) -> BullPose? {
        let progress = (elapsed - Self.chargeStart) / Self.chargeSeconds - Double(lag) * 0.011
        guard !isStill, progress >= 0, progress <= 1 else { return nil }
        return pose(atCharge: progress)
    }

    /// The charge slows to half speed as it passes the middle, so the bull is seen in full before it rushes off.
    private func pose(atCharge progress: Double) -> BullPose {
        let travel = CGFloat(progress + 0.08 * sin(2 * .pi * progress))
        let x = -bullSize.width * 0.6 + (size.width + bullSize.width * 1.2) * travel
        let stride = CGFloat(abs(sin(progress * .pi * 7)))
        let y = groundY - bullSize.height / 2 - stride * bullSize.height * 0.05
        return BullPose(center: CGPoint(x: x, y: y), tilt: .degrees(sin(progress * .pi * 14) * 2.5))
    }

    func titleProgress(at elapsed: TimeInterval, delay: TimeInterval = 0) -> Double {
        guard !isStill else { return 1 }
        return min(1, max(0, (elapsed - Self.impact - 0.05 - delay) / 0.55))
    }

    func drawTrail(in context: inout GraphicsContext, at elapsed: TimeInterval) {
        guard !isStill else { return }
        drawStreaks(in: &context, at: elapsed)
        drawPuffs(in: &context, at: elapsed)
    }

    func drawImpact(in context: inout GraphicsContext, at elapsed: TimeInterval) {
        let age = elapsed - Self.impact
        guard !isStill, age >= 0 else { return }
        drawFlash(in: &context, age: age)
        drawRings(in: &context, age: age)
        chips.draw(in: &context, at: age)
        drawStreamers(in: &context, age: age)
    }

    private func drawStreaks(in context: inout GraphicsContext, at elapsed: TimeInterval) {
        let progress = (elapsed - Self.chargeStart) / Self.chargeSeconds
        guard progress > 0, progress < 1, let bull = bullPose(at: elapsed) else { return }
        let edgeFade = min(1, progress * 6) * min(1, (1 - progress) * 6)
        for streak in streaks {
            let head = bull.center.x - bullSize.width * (0.3 + streak.lag)
            let y = groundY - bullSize.height * streak.height
            let flicker = 0.6 + 0.4 * sin(elapsed * streak.flicker + streak.lag * 10)
            let opacity = 0.5 * Double(1 - streak.lag / Streak.maxLag) * flicker * edgeFade
            var line = Path()
            line.move(to: CGPoint(x: head - streak.length, y: y))
            line.addLine(to: CGPoint(x: head, y: y))
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Casino.ivory.color(opacity: 0), Casino.ivory.color(opacity: opacity)]),
                startPoint: CGPoint(x: head - streak.length, y: y), endPoint: CGPoint(x: head, y: y))
            context.stroke(line, with: shading, style: StrokeStyle(lineWidth: streak.width, lineCap: .round))
        }
    }

    private func drawPuffs(in context: inout GraphicsContext, at elapsed: TimeInterval) {
        for puff in puffs {
            let spawnedAt = Self.chargeStart + puff.spawn * Self.chargeSeconds
            let age = elapsed - spawnedAt
            guard age >= 0, age < Self.puffSeconds else { continue }
            let hoof = pose(atCharge: puff.spawn).center.x + puff.hoof * bullSize.width
            let life = CGFloat(age / Self.puffSeconds)
            let center = CGPoint(x: hoof + puff.drift.dx * CGFloat(age), y: groundY + puff.drift.dy * CGFloat(age))
            let radius = puff.radius * (1 + 2.5 * life)
            let opacity = 0.3 * pow(Double(1 - life), 1.5)
            let cloud = Gradient(colors: [puff.shade.color(opacity: opacity), puff.shade.color(opacity: 0)])
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(cloud, center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func drawFlash(in context: inout GraphicsContext, age: TimeInterval) {
        guard age < Self.flashSeconds else { return }
        let strength = 0.55 * (1 - age / Self.flashSeconds)
        let gradient = Gradient(colors: [Color.white.opacity(strength), Casino.brass.color(opacity: strength * 0.4), .clear])
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(gradient, center: impactPoint, startRadius: 0, endRadius: size.width * 0.45))
    }

    private func drawRings(in context: inout GraphicsContext, age: TimeInterval) {
        let farthest = hypot(size.width, size.height) * 0.55
        for (delay, width, strength) in [(0.0, 18.0, 0.85), (0.12, 7.0, 0.55)] as [(TimeInterval, CGFloat, Double)] {
            let progress = (age - delay) / Self.ringSeconds
            guard progress >= 0, progress < 1 else { continue }
            let radius = farthest * CGFloat(1 - pow(1 - progress, 3))
            let ring = Path(ellipseIn: CGRect(x: impactPoint.x - radius, y: impactPoint.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(Casino.brass.mixed(0.3).color(opacity: strength * (1 - progress))),
                           lineWidth: width * CGFloat(1 - progress) + 1)
        }
    }

    private func drawStreamers(in context: inout GraphicsContext, age: TimeInterval) {
        for streamer in streamers {
            let fall = age - streamer.delay
            guard fall >= 0 else { continue }
            let time = CGFloat(fall)
            let y = streamer.start.y + streamer.speed * time
            guard y < size.height + 40 else { continue }
            let x = streamer.start.x + streamer.sway * sin(2 * .pi * streamer.swayRate * time + streamer.phase)
            let flip = cos(streamer.phase + streamer.flipRate * time)
            var piece = context
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(streamer.rotation + streamer.spin * time))
            piece.scaleBy(x: 1, y: max(0.12, abs(flip)))
            let paint = flip > 0 ? streamer.paint : streamer.paint.mixed(-0.3)
            piece.fill(Path(CGRect(x: -streamer.width / 2, y: -streamer.length / 2, width: streamer.width, height: streamer.length)),
                       with: .color(paint.color()))
        }
    }
}

extension CelebrationScene.Art {
    /// `bull` is menubar.svg drawn large; its bottom eighteenth is the ground line, which the charge leaves behind.
    init?(bull: NSImage) {
        guard let drawing = bull.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let silhouette = drawing.cropping(to: CGRect(x: 0, y: 0, width: drawing.width, height: drawing.height * 17 / 18)),
              let gold = Self.gild(silhouette) else { return nil }
        self.init(silhouette: silhouette, gold: gold)
    }

    private static func gild(_ silhouette: CGImage) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: silhouette.width, height: silhouette.height)
        let colors = [Casino.brass.mixed(0.6).cgColor(), Casino.brass.cgColor(), Casino.brassDim.cgColor()] as CFArray
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]),
              let context = CGContext(data: nil, width: silhouette.width, height: silhouette.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(silhouette, in: bounds)
        context.setBlendMode(.sourceIn)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.height), end: .zero, options: [])
        return context.makeImage()
    }
}

/// Dust kicked up by a hoof: `spawn` is how far through the charge, `hoof` the offset from the bull's centre in widths.
private struct Puff {
    let spawn: Double
    let hoof: CGFloat
    let drift: CGVector
    let radius: CGFloat
    let shade: RGB

    init() {
        spawn = Double.random(in: 0...0.95)
        hoof = Bool.random() ? CGFloat.random(in: -0.42 ... -0.3) : CGFloat.random(in: 0.1...0.25)
        drift = CGVector(dx: -CGFloat.random(in: 60...180), dy: -CGFloat.random(in: 25...80))
        radius = CGFloat.random(in: 12...30)
        shade = [Casino.ivory, Casino.brass.mixed(0.5), Casino.brass.mixed(0.25)].randomElement() ?? Casino.ivory
    }
}

/// A speed line trailing the bull: `lag` in bull widths behind it, `height` in bull heights off the ground.
private struct Streak {
    static let maxLag: CGFloat = 1.3

    let lag: CGFloat
    let height: CGFloat
    let length: CGFloat
    let width: CGFloat
    let flicker: Double

    init() {
        lag = CGFloat.random(in: 0...Self.maxLag)
        height = CGFloat.random(in: 0.08...0.92)
        length = CGFloat.random(in: 90...320)
        width = CGFloat.random(in: 1.5...4)
        flicker = Double.random(in: 18...40)
    }
}

private struct Streamer {
    let start: CGPoint
    let delay: TimeInterval
    let speed: CGFloat
    let sway: CGFloat
    let swayRate: CGFloat
    let phase: CGFloat
    let flipRate: CGFloat
    let rotation: CGFloat
    let spin: CGFloat
    let width: CGFloat
    let length: CGFloat
    let paint: RGB

    init(across size: CGSize) {
        start = CGPoint(x: CGFloat.random(in: 0...size.width), y: -CGFloat.random(in: 20...(size.height * 0.35)))
        delay = TimeInterval.random(in: 0...0.5)
        speed = CGFloat.random(in: 240...520)
        sway = CGFloat.random(in: 15...60)
        swayRate = CGFloat.random(in: 0.8...2.2)
        phase = CGFloat.random(in: 0...(2 * .pi))
        flipRate = CGFloat.random(in: 4...10)
        rotation = CGFloat.random(in: 0...(2 * .pi))
        spin = CGFloat.random(in: -3...3)
        width = CGFloat.random(in: 6...11)
        length = CGFloat.random(in: 12...22)
        paint = [Casino.brass, Casino.brass.mixed(0.45), Casino.ivory, Casino.rojo, Casino.verde.mixed(0.15), Casino.brass]
            .randomElement() ?? Casino.brass
    }
}
