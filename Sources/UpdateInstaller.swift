import Foundation

/// Builds a release from source and puts it where the running app lives. The config and the LaunchAgent stay as
/// install.sh left them.
struct UpdateInstaller {
    /// launchd hands the agent a bare PATH, and build.sh needs rsvg-convert from Homebrew besides swiftc.
    private static let toolPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    let feed: ReleaseFeed

    func install(_ release: Release, report: (String) -> Void) throws {
        let files = FileManager.default
        let workspace = Paths.updateDirectory
        try? files.removeItem(at: workspace)
        try files.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: workspace) }

        report("Downloading \(release.version)…")
        let tarball = workspace.appendingPathComponent("source.tar.gz")
        try feed.downloadSource(of: release, to: tarball)
        try run("/usr/bin/tar", ["-xzf", tarball.path, "-C", workspace.path])
        let source = try extractedSource(in: workspace)

        report("Building \(release.version)…")
        try run("/bin/bash", [source.appendingPathComponent("build.sh").path],
                environment: ["VERSION": release.version.description])
        let installed = Bundle.main.bundleURL
        let built = source.appendingPathComponent("build").appendingPathComponent(installed.lastPathComponent)
        _ = try files.replaceItemAt(installed, withItemAt: built)
    }

    /// launchd kills this process on the way, so returning means the restart has not happened yet or never will.
    func restart() throws {
        guard let label = Bundle.main.bundleIdentifier else {
            throw WatcherError.setup("the bundle has no identifier to name its LaunchAgent by")
        }
        try run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    /// GitHub wraps the source in one directory named after the repository and commit.
    private func extractedSource(in workspace: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: [.isDirectoryKey])
        let directories = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard directories.count == 1, let source = directories.first else {
            throw WatcherError.setup("expected one directory in the release tarball, found \(directories.map(\.lastPathComponent))")
        }
        return source
    }

    /// The whole transcript goes to the log; the error carries its tail, where swiftc and set -e leave the cause.
    private func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
            .merging(environment) { $1 }
            .merging(["PATH": Self.toolPaths]) { $1 }

        let transcript = Pipe()
        process.standardOutput = transcript
        process.standardError = transcript
        try process.run()
        let output = String(decoding: transcript.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let command = ([executable] + arguments).joined(separator: " ")
            Log.write("\(command) exited \(process.terminationStatus):\n\(output)")
            let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            throw WatcherError.setup("\(URL(fileURLWithPath: executable).lastPathComponent) exited \(process.terminationStatus): \(tail)")
        }
    }
}
