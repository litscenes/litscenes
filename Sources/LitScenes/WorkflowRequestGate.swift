import Foundation

/// A workflow can fan out (for example, a Scene Plan renders several images).
/// Enforce the same limits at the request boundary as well as at job admission.
actor WorkflowRequestGate {
    static let shared = WorkflowRequestGate()
    private struct Waiter {
        let id: UUID
        let lane: WorkflowLane
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var active: [UUID: WorkflowLane] = [:]
    private var waiting: [Waiter] = []

    func acquire(_ id: UUID, lane: WorkflowLane) async -> Bool {
        guard !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            waiting.append(Waiter(id: id, lane: lane, continuation: continuation))
            drain()
        }
    }

    func release(_ id: UUID) {
        active.removeValue(forKey: id)
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: index).continuation.resume(returning: false)
        }
        drain()
    }

    private func drain() {
        for waiter in waiting {
            guard active.values.filter({ $0 == waiter.lane }).count < waiter.lane.capacity else { continue }
            active[waiter.id] = waiter.lane
            waiting.removeAll { $0.id == waiter.id }
            waiter.continuation.resume(returning: true)
        }
    }

    static func lane(for metadata: InferenceTraceRequestMetadata) -> WorkflowLane {
        switch metadata.apiFamily {
        case "image", "images", "stable-image": return .image
        case "video": return .video
        case "audio", "voices": return .audio
        case "responses": return .text
        case "local_workflow": return .local
        default: return WorkflowContext.current?.lane ?? .local
        }
    }

    static func perform<Value: Sendable>(metadata: InferenceTraceRequestMetadata,
        operation: @Sendable () async throws -> Value) async throws -> Value {
        let id = UUID()
        return try await withTaskCancellationHandler {
            guard await shared.acquire(id, lane: lane(for: metadata)) else { throw CancellationError() }
            do {
                try Task.checkCancellation()
                let result = try await operation()
                await shared.release(id)
                return result
            } catch {
                await shared.release(id)
                throw error
            }
        } onCancel: {
            Task { await shared.release(id) }
        }
    }
}
