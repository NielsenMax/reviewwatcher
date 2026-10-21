import Foundation

enum MergeOutcome {
    case merged
    case mergesWhenChecksPass
}

struct GitLabClient {
    let host: String
    let token: String?

    /// launchd hands the agent a bare PATH, so glab is located explicitly.
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func locateGlab() throws -> String {
        let candidates = searchPaths.map { "\($0)/glab" }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw WatcherError.setup("glab not found in \(searchPaths.joined(separator: ", "))")
        }
        return found
    }

    func openReviewRequests(username: String) throws -> [MergeRequest] {
        let payload = try runGlab(["api", "graphql", "-f", "query=\(Self.reviewRequestsQuery)", "-f", "username=\(username)"])
        let response = try JSONDecoder().decode(ReviewRequestsResponse.self, from: payload)
        guard let user = response.data.user else {
            throw WatcherError.setup("GitLab has no user @\(username) on \(host)")
        }
        return user.reviewRequestedMergeRequests.nodes
    }

    /// The version endpoint returns every file at once, together with the commit those diffs were taken at.
    func latestDiff(of mergeRequest: MergeRequest) throws -> DiffVersion {
        let versions = try JSONDecoder().decode([VersionSummary].self,
                                                from: runGlab(["api", "\(mergeRequest.apiPath)/versions"]))
        guard let newest = versions.first else {
            throw WatcherError.setup("\(mergeRequest.label) has no diff versions yet")
        }
        let payload = try runGlab(["api", "\(mergeRequest.apiPath)/versions/\(newest.id)"])
        return try JSONDecoder().decode(DiffVersion.self, from: payload)
    }

    func fileLines(projectID: Int, path: String, at ref: String) throws -> [String] {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters) else {
            throw WatcherError.setup("could not encode the path \(path)")
        }
        let payload = try runGlab(["api", "projects/\(projectID)/repository/files/\(encodedPath)/raw?ref=\(ref)"])
        guard let text = String(data: payload, encoding: .utf8) else {
            throw WatcherError.setup("\(path) at \(ref.prefix(8)) is not UTF-8 text")
        }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// GitLab reads a slash in the file path as part of the route, so every reserved character is escaped.
    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    func approve(_ mergeRequest: MergeRequest) throws {
        _ = try runGlab(["api", "-X", "POST", "\(mergeRequest.apiPath)/approve"] + headPin(mergeRequest))
    }

    func unapprove(_ mergeRequest: MergeRequest) throws {
        _ = try runGlab(["api", "-X", "POST", "\(mergeRequest.apiPath)/unapprove"])
    }

    /// Auto-merge merges at once when every check already passes, and otherwise waits on them.
    func merge(_ mergeRequest: MergeRequest) throws -> MergeOutcome {
        let arguments = ["api", "-X", "PUT", "\(mergeRequest.apiPath)/merge", "-F", "auto_merge=true"]
        let payload = try runGlab(arguments + headPin(mergeRequest))
        let result = try JSONDecoder().decode(MergeResult.self, from: payload)
        return result.state == "merged" ? .merged : .mergesWhenChecksPass
    }

    /// GitLab answers 409 when the branch moved past `sha`, so a push made after the list loaded is never approved unseen.
    private func headPin(_ mergeRequest: MergeRequest) throws -> [String] {
        guard let sha = mergeRequest.headSHA else {
            throw WatcherError.setup("\(mergeRequest.label) has no diff head to pin the change to")
        }
        return ["-f", "sha=\(sha)"]
    }

    private static let reviewRequestsQuery = """
        query($username: String!) {
          user(username: $username) {
            reviewRequestedMergeRequests(state: opened, first: 100, sort: UPDATED_DESC) {
              nodes {
                iid title webUrl updatedAt projectId diffHeadSha
                sourceBranch targetBranch sourceProjectId
                project { fullPath }
                author { username }
                diffStatsSummary { additions deletions fileCount }
                headPipeline { status }
                approvedBy { nodes { username } }
                detailedMergeStatus
                autoMergeEnabled conflicts draft
                userPermissions { canMerge canApprove }
              }
            }
          }
        }
        """

    private struct ReviewRequestsResponse: Decodable {
        let data: Payload

        struct Payload: Decodable {
            let user: User?
        }

        struct User: Decodable {
            let reviewRequestedMergeRequests: Connection
        }

        struct Connection: Decodable {
            let nodes: [MergeRequest]
        }
    }

    private struct MergeResult: Decodable {
        let state: String
    }

    private struct VersionSummary: Decodable {
        let id: Int
    }

    private func runGlab(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try Self.locateGlab())
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPaths.joined(separator: ":") + ":/bin"
        environment["GITLAB_HOST"] = host
        if let token { environment["GITLAB_TOKEN"] = token }
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw WatcherError.glab(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}
