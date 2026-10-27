import SwiftUI

struct CelebrationTimeline: View {
    let scene: CelebrationScene
    let startedAt: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            CelebrationView(scene: scene, elapsed: timeline.date.timeIntervalSince(startedAt))
        }
    }
}

struct CelebrationView: View {
    let scene: CelebrationScene
    let elapsed: TimeInterval

    private static let ghostCount = 6

    var body: some View {
        ZStack {
            backdrop
            Canvas { context, _ in scene.drawTrail(in: &context, at: elapsed) }
            ForEach((1...Self.ghostCount).reversed(), id: \.self) { lag in
                bull(lag: lag)
            }
            bull(lag: 0)
            Canvas { context, _ in scene.drawImpact(in: &context, at: elapsed) }
            billing
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .opacity(scene.visibility(at: elapsed))
        .allowsHitTesting(false)
    }

    private var backdrop: some View {
        RadialGradient(colors: [Casino.feltDeep.color(opacity: 0.66), Casino.ink.color(opacity: 0.9)],
                       center: .center, startRadius: 0,
                       endRadius: max(scene.size.width, scene.size.height) * 0.75)
    }

    @ViewBuilder
    private func bull(lag: Int) -> some View {
        if let pose = scene.bullPose(at: elapsed, lag: lag) {
            let isLeading = lag == 0
            Image(decorative: scene.art.gold, scale: 1)
                .resizable()
                .overlay(isLeading ? shine : nil)
                .frame(width: scene.bullSize.width, height: scene.bullSize.height)
                .rotationEffect(pose.tilt, anchor: .bottom)
                .shadow(color: Casino.brass.color(opacity: isLeading ? 0.6 : 0), radius: 30)
                .opacity(isLeading ? 1 : 0.22 * (1 - Double(lag) / Double(Self.ghostCount + 1)))
                .position(pose.center)
        }
    }

    private var shine: some View {
        let sweep = CGFloat((elapsed * 2).truncatingRemainder(dividingBy: 1))
        return LinearGradient(stops: [.init(color: .clear, location: 0),
                                      .init(color: .white.opacity(0.75), location: 0.5),
                                      .init(color: .clear, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: scene.bullSize.width * 0.28)
            .offset(x: (sweep - 0.5) * scene.bullSize.width * 1.6)
            .frame(width: scene.bullSize.width, height: scene.bullSize.height)
            .mask(Image(decorative: scene.art.silhouette, scale: 1).resizable())
    }

    private var billing: some View {
        let height = scene.size.height
        let entrance = scene.titleProgress(at: elapsed)
        let details = scene.titleProgress(at: elapsed, delay: 0.25)
        let gold = LinearGradient(colors: [Casino.brass.mixed(0.65).color(), Casino.brass.color(), Casino.brassDim.color()],
                                  startPoint: .top, endPoint: .bottom)
        let rule = LinearGradient(colors: [Casino.brass.color(opacity: 0), Casino.brass.color(), Casino.brass.color(opacity: 0)],
                                  startPoint: .leading, endPoint: .trailing)
        return VStack(spacing: height * 0.014) {
            Text("¡OLÉ!")
                .font(.system(size: height * 0.032, weight: .heavy))
                .kerning(height * 0.016)
                .foregroundStyle(Casino.brass.color())
            Text("Merged")
                .font(Casino.display(height * 0.19))
                .foregroundStyle(gold)
                .shadow(color: Casino.brass.color(opacity: 0.55), radius: 28)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
                .fixedSize()
            Capsule()
                .fill(rule)
                .frame(width: scene.size.width * 0.32 * details, height: 2)
            VStack(spacing: 6) {
                Text(scene.label)
                    .font(Casino.mono(height * 0.02))
                    .foregroundStyle(Casino.chalk.color())
                Text(scene.title)
                    .font(.system(size: height * 0.028, weight: .medium))
                    .foregroundStyle(Casino.ivory.color())
                    .lineLimit(1)
                    .frame(maxWidth: scene.size.width * 0.6)
            }
            .opacity(details)
            .offset(y: 14 * (1 - details))
        }
        .scaleEffect(Self.springScale(entrance))
        .blur(radius: 16 * (1 - min(1, entrance * 2)))
        .opacity(min(1, entrance * 3))
        .position(x: scene.size.width / 2, y: height * 0.36)
    }

    private static func springScale(_ progress: Double) -> CGFloat {
        CGFloat(1 + 0.6 * exp(-5 * progress) * cos(9 * progress))
    }
}
