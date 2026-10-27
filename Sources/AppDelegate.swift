import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var poller: ReviewPoller?
    private var epicPoller: EpicPoller?
    private var statusItem: StatusItemController?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.mainMenu = Self.keyEquivalentsMenu()
        let notifier = Notifier()
        notifier.requestAuthorization()
        let updater = Updater(notifier: notifier)

        do {
            let config = try Config.load()
            let client = GitLabClient(host: config.host, token: try loadToken())
            let list = ReviewList(username: config.username, client: client)
            let poller = ReviewPoller(config: config, client: client, notifier: notifier, list: list)
            list.refresh = { [weak poller] in poller?.refresh() }
            let celebration = MergeCelebration()
            list.celebrate = { celebration.play(for: $0) }

            let jiraClient = JiraClient()
            let tickets = TicketList(email: config.jira.email, client: jiraClient)
            let epicPoller = EpicPoller(config: config, client: jiraClient, notifier: notifier, list: tickets)
            tickets.refresh = { [weak epicPoller] in epicPoller?.refresh() }
            tickets.acknowledge = { [weak epicPoller] action, key in epicPoller?.acknowledge(action, on: key) }

            let settings = Settings(config: config) { [weak poller, weak epicPoller] in
                poller?.apply($0)
                epicPoller?.apply($0)
            }
            statusItem = StatusItemController(list: list,
                                              tickets: tickets,
                                              epicSearch: EpicSearch(client: jiraClient),
                                              argo: ArgoList(client: ArgoClient()),
                                              settings: settings,
                                              updater: updater,
                                              diffWindows: DiffWindows(list: list, client: client, settings: settings),
                                              settingsWindow: SettingsWindow(settings: settings, updater: updater),
                                              rouletteWindow: RouletteWindow {
                                                  RouletteModel(service: try RouletteService(gitlab: client, jira: jiraClient,
                                                                                             config: config.roulette,
                                                                                             emailDomain: config.jira.emailDomain),
                                                                jiraSite: config.jira.site)
                                              })
            poller.start()
            epicPoller.start()
            updater.start()
            observeSleep(poller, epicPoller)
            self.poller = poller
            self.epicPoller = epicPoller
            self.updater = updater
        } catch {
            Log.write("startup failed: \(error.localizedDescription)")
            NSApplication.shared.terminate(nil)
        }
    }

    /// Display sleep stands in for "user is away": no point spending battery polling an empty desk.
    private func observeSleep(_ poller: ReviewPoller, _ epicPoller: EpicPoller) {
        let center = NSWorkspace.shared.notificationCenter
        for asleep in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: asleep, object: nil, queue: .main) { _ in
                poller.pause()
                epicPoller.pause()
            }
        }
        for awake in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: awake, object: nil, queue: .main) { _ in
                poller.resume()
                epicPoller.resume()
            }
        }
    }

    /// An agent app shows no menu bar, yet key equivalents still route through the main menu;
    /// this one gives the diff and settings windows ⌘W, ⌘C, ⌘V and ⌘A.
    private static func keyEquivalentsMenu() -> NSMenu {
        let shortcuts = NSMenu()
        shortcuts.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        shortcuts.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        shortcuts.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
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
