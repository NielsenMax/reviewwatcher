import Foundation

/// What a merge request must meet before it raises a notification. A review request that misses
/// them is held and announced once it meets them, rather than dropped.
struct NotificationGate: Equatable {
    enum Pipeline: String, Codable, CaseIterable {
        case any
        case notFailed
        case passed
    }

    var pipeline = Pipeline.any
    var requiresNoConflicts = false
    var requiresNotDraft = false

    /// A merge request without a pipeline passes the pipeline check: there is nothing to wait for.
    func admits(_ mergeRequest: MergeRequest) -> Bool {
        if requiresNoConflicts, mergeRequest.hasConflicts { return false }
        if requiresNotDraft, mergeRequest.isDraft { return false }
        guard let status = mergeRequest.pipeline else { return true }
        switch pipeline {
        case .any: return true
        case .notFailed: return status != .failed
        case .passed: return status == .success
        }
    }
}

extension NotificationGate: Codable {
    private enum CodingKeys: String, CodingKey {
        case pipeline
        case requiresNoConflicts = "noConflicts"
        case requiresNotDraft = "notDraft"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pipeline = try container.decodeIfPresent(Pipeline.self, forKey: .pipeline) ?? .any
        requiresNoConflicts = try container.decodeIfPresent(Bool.self, forKey: .requiresNoConflicts) ?? false
        requiresNotDraft = try container.decodeIfPresent(Bool.self, forKey: .requiresNotDraft) ?? false
    }
}
