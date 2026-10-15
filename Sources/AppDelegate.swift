import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var poller: ReviewPoller?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.mainMenu = Self.keyEquivalentsMenu()
        let notifier = Notifier()
        notifier.requestAuthorization()

        do {
            let config = try Config.load()
            let client = GitLabClient(host: config.host, token: try loadToken())
            let list = ReviewList(username: config.username, client: client)
            let poller = ReviewPoller(config: config, client: client, notifier: notifier, list: list)
            list.refresh = { [weak poller] in poller?.refresh() }
            let settings = Settings(config: config) { [weak poller] in poller?.apply($0) }
            statusItem = StatusItemController(list: list,
                                              diffWindows: DiffWindows(list: list, client: client, settings: settings),
                                              settingsWindow: SettingsWindow(settings: settings))
            poller.start()
            observeSleep(poller)
            self.poller = poller
        } catch {
            Log.write("startup failed: \(error.localizedDescription)")
            NSApplication.shared.terminate(nil)
        }
    }

    /// Display sleep stands in for "user is away": no point spending battery polling an empty desk.
    private func observeSleep(_ poller: ReviewPoller) {
        let center = NSWorkspace.shared.notificationCenter
        for asleep in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: asleep, object: nil, queue: .main) { _ in poller.pause() }
        }
        for awake in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: awake, object: nil, queue: .main) { _ in poller.resume() }
        }
    }

    /// An agent app shows no menu bar, yet key equivalents still route through the main menu;
    /// this one gives the diff windows ⌘W, ⌘C and ⌘A.
    private static func keyEquivalentsMenu() -> NSMenu {
        let shortcuts = NSMenu()
        shortcuts.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        shortcuts.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        shortcuts.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let holder = NSMenuItem()
        holder.submenu = shortcuts
        let root = NSMenu()
        root.addItem(holder)
        return root
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo[Notifier.urlKey] as? String,
           let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func loadToken() throws -> String? {
        guard let token = try? String(contentsOf: Paths.tokenFile, encoding: .utf8) else {
            // Absent a token file, glab falls back to its own stored credentials.
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
