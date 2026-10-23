import Foundation

/// What the popover's Argo tab shows. Owned by the main queue; argocd runs on a global queue and reports back.
/// Nothing polls in the background: the list loads when the tab is looked at, and an app is followed only
/// while a sync started here is running.
final class ArgoList: ObservableObject {
    enum Filter: Hashable {
        case outOfSync, all
    }

    enum LoadState {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    enum Progress {
        case starting
        case syncing
        case done(String)
        case failed(String)
    }

    @Published private(set) var apps: [ArgoApp] = []
    @Published private(set) var loadState = LoadState.idle
    @Published var filter = Filter.outOfSync
    @Published var query = ""
    @Published private(set) var progress: [String: Progress] = [:]
    @Published private(set) var armedID: String?
    @Published private(set) var server: String?

    private let client: ArgoClient
    private var isLoading = false
    private var disarm: DispatchWorkItem?

    private static let armedSeconds = 4.0
    private static let followInterval = 3.0
    /// How long a sync is followed before the row stops waiting on it.
    private static let followLimit: TimeInterval = 15 * 60

    init(client: ArgoClient) {
        self.client = client
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        loadState = .loading
        let knownServer = server
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let outcome = Result { (server: try knownServer ?? client.server(), apps: try client.applications()) }
            DispatchQueue.main.async {
                self.isLoading = false
                switch outcome {
                case .success(let loaded):
                    self.server = loaded.server
                    self.apps = loaded.apps
                    self.loadState = .loaded(Date())
                case .failure(let error):
                    Log.write("argo refresh failed: \(error.localizedDescription)")
                    self.loadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    var outOfSyncCount: Int {
        apps.filter(\.isOutOfSync).count
    }

    /// Out-of-sync apps lead; an app with a sync started here stays listed after it comes back in sync.
    var visibleApps: [ArgoApp] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return apps
            .filter { filter == .all || $0.isOutOfSync || progress[$0.id] != nil }
            .filter { app in
                let haystack = "\(app.name) \(app.project) \(app.destination)".lowercased()
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                lhs.isOutOfSync != rhs.isOutOfSync
                    ? lhs.isOutOfSync
                    : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func browseURL(for app: ArgoApp) -> URL? {
        server.flatMap { URL(string: "https://\($0)/applications/\(app.namespace)/\(app.name)") }
    }

    /// The first click arms the sync and the second fires it, since a slip here deploys to production.
    func triggerSync(of app: ArgoApp) {
        disarm?.cancel()
        guard armedID == app.id else {
            armedID = app.id
            let disarm = DispatchWorkItem { [weak self] in self?.armedID = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.armedSeconds, execute: disarm)
            self.disarm = disarm
            return
        }
        armedID = nil
        progress[app.id] = .starting
        let previousStart = app.operation?.startedAt
        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let outcome = Result { try client.sync(app.name) }
            DispatchQueue.main.async {
                switch outcome {
                case .success:
                    Log.write("Sync started: \(app.id)")
                    self.progress[app.id] = .syncing
                    self.follow(app, after: previousStart, since: Date())
                case .failure(let error):
                    Log.write("Sync failed for \(app.id): \(error.localizedDescription)")
                    self.progress[app.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Waits for an operation that started after `previousStart`, so the last sync's verdict is not read as this one's.
    private func follow(_ app: ArgoApp, after previousStart: String?, since started: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.followInterval) { [client] in
            DispatchQueue.global(qos: .utility).async {
                let outcome = Result { try client.application(named: app.name) }
                DispatchQueue.main.async {
                    switch outcome {
                    case .failure(let error):
                        self.progress[app.id] = .failed(error.localizedDescription)
                    case .success(let current):
                        self.replace(current)
                        guard let operation = current.operation, operation.startedAt != previousStart, !operation.isRunning else {
                            if Date().timeIntervalSince(started) < Self.followLimit {
                                self.follow(app, after: previousStart, since: started)
                            } else {
                                self.progress[app.id] = .failed("still syncing after \(Int(Self.followLimit / 60)) minutes")
                            }
                            return
                        }
                        Log.write("Sync \(operation.phase.lowercased()): \(app.id)")
                        self.progress[app.id] = operation.hasFailed
                            ? .failed(operation.message ?? operation.phase)
                            : .done(current.isOutOfSync ? "Synced, still out of sync" : "Synced")
                    }
                }
            }
        }
    }

    private func replace(_ app: ArgoApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index] = app
    }
}
