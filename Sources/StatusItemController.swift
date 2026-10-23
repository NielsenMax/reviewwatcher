import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let list: ReviewList
    private let tickets: TicketList
    private let argo: ArgoList
    private let tabs = PopoverTabs()
    private var badgeUpdates: AnyCancellable?

    init(list: ReviewList, tickets: TicketList, epicSearch: EpicSearch, argo: ArgoList, settings: Settings,
         diffWindows: DiffWindows, settingsWindow: SettingsWindow, rouletteWindow: RouletteWindow) {
        self.list = list
        self.tickets = tickets
        self.argo = argo
        super.init()

        let reviews = ReviewListView(list: list, openDiff: diffWindows.show, openSettings: settingsWindow.show)
        let epic = TicketListView(list: tickets, settings: settings, search: epicSearch,
                                  openSettings: settingsWindow.show)
        let openRoulette = { [popover] in
            popover.performClose(nil)
            rouletteWindow.show()
        }
        let host = NSHostingController(rootView: PopoverView(tabs: tabs, reviews: reviews, epic: epic,
                                                             argo: ArgoListView(list: argo, openSettings: settingsWindow.show),
                                                             openRoulette: openRoulette))
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
        tickets.refresh()
        if tabs.selection == .argo { argo.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
