import Foundation
import Testing
@testable import LitScenes

// A finished workflow job must not capture follow-up work that inherited its
// task-local context: the coordinator treats that context as none, nested
// runs and owned requests open their own job, and the provider gate fails
// instead of waiting for an admission that cannot come.

private struct FollowUpTimeout: Error {}

private func withinFiveSeconds<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(5)); throw FollowUpTimeout() }
        guard let first = try await group.next() else { throw FollowUpTimeout() }
        group.cancelAll()
        return first
    }
}

private func followUpMetadata() -> InferenceTraceRequestMetadata {
    InferenceTraceRequestMetadata(provider: "openai", apiFamily: "responses", operation: "follow_up_test",
        projectId: "", runId: "", workflowName: "story", workflowStep: "follow_up")
}

@MainActor
struct WorkflowContextInheritanceTests {
    private func finishedContext() async throws -> WorkflowContext {
        let captured = await WorkflowCoordinator.shared.run(project: nil, workflow: "follow_up_parent", lane: .local,
            failure: Optional<WorkflowContext>.none) { WorkflowContext.current }
        let context = try #require(captured)
        #expect(!WorkflowCoordinator.shared.isLive(context.jobId), "the parent job has finished")
        return context
    }

    @Test func nestedRunInsideAFinishedJobOpensItsOwnJob() async throws {
        let stale = try await finishedContext()
        let observed = await WorkflowContext.$current.withValue(stale) {
            await WorkflowCoordinator.shared.run(project: nil, workflow: "follow_up_child", lane: .local, failure: "") {
                WorkflowContext.current?.jobId ?? ""
            }
        }
        #expect(!observed.isEmpty)
        #expect(observed != stale.jobId)
    }

    @Test func ownedRequestInsideAFinishedJobOpensItsOwnJob() async throws {
        let stale = try await finishedContext()
        let observed: String? = try await WorkflowContext.$current.withValue(stale) {
            try await withinFiveSeconds {
                try await WorkflowHTTP.owned(metadata: followUpMetadata()) { WorkflowContext.current?.jobId }
            }
        }
        let fresh = try #require(observed)
        #expect(fresh != stale.jobId)
        #expect(!WorkflowCoordinator.shared.isLive(fresh), "the fresh job closes with the request")
    }

    @Test func providerGateFailsFastInsideAFinishedJob() async throws {
        let stale = try await finishedContext()
        do {
            try await WorkflowContext.$current.withValue(stale) {
                try await withinFiveSeconds {
                    try await WorkflowCoordinator.shared.providerStarted(followUpMetadata(), traceId: "itrace_follow_up_test")
                }
            }
            Issue.record("a request inside a finished job must not proceed")
        } catch {
            #expect(!(error is FollowUpTimeout), "the gate must fail, not wait: \(error)")
            #expect(error.localizedDescription.contains("already finished"))
        }
    }

    @Test func liveJobStillOwnsItsOwnRequests() async throws {
        // Inheritance is scoped to the same project, so the sanity check needs one.
        let now = DateFormats.now()
        let project = ProjectRecord(projectId: "project_follow_up_test", name: "Follow-up", createdAt: now, updatedAt: now, sessionCount: 0)
        let observed = await WorkflowCoordinator.shared.run(project: project, workflow: "follow_up_live", lane: .local, failure: "") {
            let own = WorkflowContext.current?.jobId ?? ""
            let nested = await WorkflowCoordinator.shared.run(project: project, workflow: "follow_up_live_nested", lane: .local, failure: "") {
                WorkflowContext.current?.jobId ?? ""
            }
            return own == nested ? own : ""
        }
        #expect(!observed.isEmpty, "a live job still absorbs nested work instead of opening a second job")
    }
}
