import Foundation

/// Checks for a newer release every hour and installs one only when asked. Checks and installs take turns on
/// `queue`; `state` changes on the main queue.
final class Updater: ObservableObject {
    enum State {
        case unchecked
        case upToDate(Date)
        case checkFailed(String)
        case available(Release)
        case installing(Release, String)
        case installFailed(Release, String)
    }

    @Published private(set) var state = State.unchecked

    /// What build.sh baked in: a release such as `1.2.3`, or `git describe` output for a build that is not one.
    let runningVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    private let feed = ReleaseFeed()
    private let installer: UpdateInstaller
    private let notifier: Notifier
    private let queue = DispatchQueue(label: "app.reviewwatcher.update")
    private var timer: DispatchSourceTimer?
    private var announced: ReleaseVersion?

    private static let checkInterval: TimeInterval = 3600

    init(notifier: Notifier) {
        self.notifier = notifier
        installer = UpdateInstaller(feed: feed)
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.check() }
            timer.schedule(deadline: .now(), repeating: Self.checkInterval)
            self.timer = timer
            timer.resume()
            Log.write("running version \(runningVersion), checking \(ReleaseFeed.repository) for releases hourly")
        }
    }

    func checkNow() {
        queue.async { [weak self] in self?.check() }
    }

    /// Called from the main queue, so the state flips before a second click can land.
    func install(_ release: Release) {
        state = .installing(release, "Starting…")
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try installer.install(release) { step in self.publish(.installing(release, step)) }
                Log.write("Installed \(release.version), restarting")
                publish(.installing(release, "Restarting…"))
                try installer.restart()
            } catch {
                Log.write("could not update to \(release.version): \(error.localizedDescription)")
                publish(.installFailed(release, error.localizedDescription))
            }
        }
    }

    func changes(in release: Release) -> URL {
        feed.changes(from: ReleaseVersion(bundleVersion: runningVersion), to: release)
    }

    /// A build no release version can be read from is older than any release.
    private func check() {
        do {
            let running = ReleaseVersion(bundleVersion: runningVersion)
            guard let latest = try feed.latest(), running.map({ latest.version > $0 }) ?? true else {
                publish(.upToDate(Date()))
                return
            }
            publish(.available(latest))
            guard announced != latest.version else { return }
            announced = latest.version
            Log.write("Release \(latest.version) is available")
            notifier.post(latest, changes: changes(in: latest))
        } catch {
            Log.write("could not check for updates: \(error.localizedDescription)")
            publish(.checkFailed(error.localizedDescription))
        }
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.state = state }
    }
}
