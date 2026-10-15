import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let list: ReviewList
    private var badgeUpdates: AnyCancellable?

    init(list: ReviewList, diffWindows: DiffWindows, settingsWindow: SettingsWindow) {
        self.list = list
        super.init()

        let host = NSHostingController(rootView: ReviewListView(list: list,
                                                                openDiff: diffWindows.show,
                                                                openSettings: settingsWindow.show))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        if let button = item.button {
            let icon = Bundle.main.image(forResource: "menubar")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover)
        }

        // @Published emits before the property changes, so the badge reads the value handed to it.
        badgeUpdates = list.$mergeRequests.sink { [weak self] mergeRequests in
            self?.showBadge(for: mergeRequests)
        }
    }

    /// Counts only what still waits on this reviewer's approval; approved-but-unmerged is someone else's move.
    private func showBadge(for mergeRequests: [MergeRequest]) {
        let awaiting = mergeRequests.filter { !$0.isApproved(by: list.username) }.count
        item.button?.title = awaiting > 0 ? " \(awaiting)" : ""
        item.button?.toolTip = "\(awaiting) review \(awaiting == 1 ? "request" : "requests") awaiting your approval"
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        list.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
