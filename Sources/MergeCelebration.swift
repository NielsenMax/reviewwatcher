import AppKit
import SwiftUI

/// Plays the celebration over the screen in use, above every window and space, letting every click through.
/// Main queue only.
final class MergeCelebration {
    var isEnabled: Bool
    private let art: CelebrationScene.Art?
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        art = Bundle.main.image(forResource: "bull").flatMap(CelebrationScene.Art.init(bull:))
        if art == nil { Log.write("merge celebration disabled: bull.png is missing from the app bundle") }
    }

    func play(for mergeRequest: MergeRequest) {
        guard isEnabled, let art, let screen = NSScreen.main else { return }
        dismiss()
        let scene = CelebrationScene(size: screen.frame.size, art: art, label: mergeRequest.label, title: mergeRequest.title,
                                     isStill: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CelebrationTimeline(scene: scene, startedAt: Date()))
        panel.orderFrontRegardless()
        self.panel = panel
        Bellow.play()

        let dismissal = DispatchWorkItem { [weak self] in self?.dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + CelebrationScene.duration, execute: dismissal)
        self.dismissal = dismissal
    }

    private func dismiss() {
        dismissal?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}
