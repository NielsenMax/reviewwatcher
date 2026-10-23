import Foundation

struct Release {
    let version: ReleaseVersion
    /// The tag's commit when it was read. The download names this commit, so a tag moved since is not followed.
    let commit: String
}

/// The repository's release tags and their source, read from GitHub without a token, which allows 60 requests an
/// hour per address.
struct ReleaseFeed {
    static let repository = "NielsenMax/reviewwatcher"

    private struct Tag: Decodable {
        struct Commit: Decodable {
            let sha: String
        }

        let name: String
        let commit: Commit
    }

    func latest() throws -> Release? {
        let data = try fetch(api("tags?per_page=100"))
        guard let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
            throw WatcherError.github("expected a list of tags, got \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return tags
            .compactMap { tag in ReleaseVersion(tag: tag.name).map { Release(version: $0, commit: tag.commit.sha) } }
            .max { $0.version < $1.version }
    }

    func downloadSource(of release: Release, to tarball: URL) throws {
        try fetch(api("tarball/\(release.commit)")).write(to: tarball)
    }

    func changes(from running: ReleaseVersion?, to release: Release) -> URL {
        let page = running.map { "compare/\($0.tag)...\(release.version.tag)" } ?? "commits/\(release.version.tag)"
        return URL(string: "https://github.com/\(Self.repository)/\(page)")!
    }

    private func api(_ path: String) -> URL {
        URL(string: "https://api.github.com/repos/\(Self.repository)/\(path)")!
    }

    /// Blocks the calling queue, as glab and acli calls do.
    private func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        var outcome: Result<Data, Error> = .failure(WatcherError.github("no answer from \(url.absoluteString)"))
        let answered = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { answered.signal() }
            if let error {
                outcome = .failure(error)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data ?? Data()
            outcome = status == 200
                ? .success(body)
                : .failure(WatcherError.github("\(url.path) answered \(status): \(String(decoding: body.prefix(200), as: UTF8.self))"))
        }.resume()
        answered.wait()
        return try outcome.get()
    }
}
