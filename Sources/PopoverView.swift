import SwiftUI

/// Which tab the popover shows. Lives as long as the app, so reopening the popover keeps the last tab.
final class PopoverTabs: ObservableObject {
    enum Tab {
        case reviews
        case epic
    }

    @Published var selection = Tab.reviews
}

struct PopoverView: View {
    @ObservedObject var tabs: PopoverTabs
    let reviews: ReviewListView
    let epic: TicketListView

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tabs.selection) {
                Text("Reviews").tag(PopoverTabs.Tab.reviews)
                Text("Epic").tag(PopoverTabs.Tab.epic)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 10)
            switch tabs.selection {
            case .reviews: reviews
            case .epic: epic
            }
        }
    }
}
