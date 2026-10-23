import Foundation

/// One Argo CD Application, reduced to what the Argo tab shows.
struct ArgoApp: Identifiable, Equatable {
    let name: String
    let namespace: String
    let project: String
    let destination: String
    let isAutoSynced: Bool
    /// Synced, OutOfSync or Unknown.
    let sync: String
    /// Healthy, Progressing, Degraded, Suspended, Missing or Unknown.
    let health: String
    let operation: Operation?

    struct Operation: Equatable {
        /// Running, Terminating, Succeeded, Failed or Error.
        let phase: String
        let message: String?
        let startedAt: String?

        var isRunning: Bool {
            phase == "Running" || phase == "Terminating"
        }

        var hasFailed: Bool {
            phase == "Failed" || phase == "Error"
        }
    }

    var id: String { "\(namespace)/\(name)" }

    var isOutOfSync: Bool {
        sync != "Synced"
    }
}

extension ArgoApp: Decodable {
    private enum CodingKeys: String, CodingKey {
        case metadata, spec, status
    }

    private struct Metadata: Decodable {
        let name: String
        let namespace: String
    }

    private struct Spec: Decodable {
        let project: String
        let destination: Destination
        let syncPolicy: SyncPolicy?
    }

    private struct Destination: Decodable {
        let server: String?
        let name: String?
        let namespace: String?
    }

    private struct SyncPolicy: Decodable {
        let automated: Automated?
    }

    private struct Automated: Decodable {}

    private struct Status: Decodable {
        let sync: SyncStatus?
        let health: HealthStatus?
        let operationState: OperationState?
    }

    private struct SyncStatus: Decodable {
        let status: String?
    }

    private struct HealthStatus: Decodable {
        let status: String?
    }

    private struct OperationState: Decodable {
        let phase: String
        let message: String?
        let startedAt: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = try container.decode(Metadata.self, forKey: .metadata)
        let spec = try container.decode(Spec.self, forKey: .spec)
        let status = try container.decodeIfPresent(Status.self, forKey: .status)
        name = metadata.name
        namespace = metadata.namespace
        project = spec.project
        destination = spec.destination.namespace ?? spec.destination.name ?? spec.destination.server ?? "?"
        isAutoSynced = spec.syncPolicy?.automated != nil
        sync = status?.sync?.status ?? "Unknown"
        health = status?.health?.status ?? "Unknown"
        operation = status?.operationState.map {
            Operation(phase: $0.phase, message: $0.message, startedAt: $0.startedAt)
        }
    }
}
