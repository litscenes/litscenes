import Foundation

/// Retry ownership belongs to the request stage, not to a whole paid workflow.
enum WorkflowHTTP {
    /// Older clients still get a durable lifecycle even before their parent
    /// workflow has adopted a higher-level job. Explicit workflow wrappers group
    /// these stages into one job through the inherited task context.
    static func owned<Value: Sendable>(metadata: InferenceTraceRequestMetadata,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if WorkflowContext.current != nil { return try await operation() }
        let now = DateFormats.now()
        let project = metadata.projectId.isEmpty ? nil : ProjectRecord(projectId: metadata.projectId,
            name: metadata.projectId, createdAt: now, updatedAt: now, sessionCount: 0)
        let result: Result<Value, Error> = await WorkflowCoordinator.shared.run(project: project,
            workflow: [metadata.workflowName, metadata.operation].filter { !$0.isEmpty }.joined(separator: "."),
            artifactType: metadata.artifactType, artifactId: metadata.artifactId,
            lane: WorkflowRequestGate.lane(for: metadata), recipeJSON: metadata.requestTextJSON,
            failure: .failure(CancellationError())) {
                do { return .success(try await operation()) }
                catch { return .failure(error) }
            }
        return try result.get()
    }

    static func scoped(_ metadata: InferenceTraceRequestMetadata) -> InferenceTraceRequestMetadata {
        guard let context = WorkflowContext.current else { return metadata }
        var result = metadata
        if result.projectId.isEmpty { result.projectId = context.projectId }
        if result.runId.isEmpty { result.runId = context.jobId }
        if result.traceGroupId.isEmpty { result.traceGroupId = context.jobId }
        if result.workflowName.isEmpty { result.workflowName = context.workflow }
        if result.artifactType.isEmpty { result.artifactType = context.artifactType }
        if result.artifactId.isEmpty { result.artifactId = context.artifactId }
        return result
    }

    static func send<Value: Sendable>(request: URLRequest, recordedRequest: URLRequest?, metadata: InferenceTraceRequestMetadata,
        bytes: @Sendable (Value) -> Data, operation: @Sendable (URLRequest) async throws -> (Value, URLResponse)) async throws -> (Value, URLResponse) {
        let submission = !["media_transfer", "pricing"].contains(metadata.apiFamily) && !["GET", "HEAD"].contains(request.httpMethod ?? "GET")
        var retries = 0
        while true {
            try Task.checkCancellation()
            do {
                let result = try await WorkflowRequestGate.perform(metadata: metadata) { try await operation(request) }
                guard let http = result.1 as? HTTPURLResponse,
                      let failure = ProviderFailure.classify(provider: metadata.provider, status: http.statusCode, data: bytes(result.0), submission: submission) else { return result }
                // Retain each rejected attempt even when a later attempt recovers.
                _ = await InferenceTraceStore.shared.record(request: recordedRequest ?? request, metadata: metadata,
                    response: http, responseBody: bytes(result.0), latencyMs: 0)
                if failure.acceptanceUnknown {
                    await WorkflowCoordinator.shared.markUncertain(failure)
                    throw failure
                }
                if failure.transient, retries < 2 {
                    let serverDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                    let delay = max(serverDelay, retries == 0 ? 2 : 5)
                    retries += 1
                    if let context = WorkflowContext.current {
                        await WorkflowCoordinator.shared.transition(context.jobId, phase: "Retry \(retries) of 2", message: failure.message)
                    }
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                if failure.accountBlocked || failure.transient {
                    // Fail fast: a silent hold reads as a stuck render, and no
                    // automatic resend can succeed until the account changes.
                    // The failure carries the provider's own explanation to the
                    // artifact that asked for the work.
                    throw failure
                }
                return result
            } catch let failure as ProviderFailure {
                throw failure
            } catch {
                if error is CancellationError || Task.isCancelled || error is ImagePromptPersistenceFailure { throw error }
                if submission {
                    let failure = ProviderFailure(provider: metadata.provider,
                        statusCode: 0, code: "transport_interrupted", message: "No complete submission response was received. Review provider acceptance before retrying.",
                        accountBlocked: false, transient: false, acceptanceUnknown: true)
                    await WorkflowCoordinator.shared.markUncertain(failure)
                    throw failure
                }
                if retries < 2 {
                    retries += 1
                    try await Task.sleep(for: .seconds(retries == 1 ? 2 : 5))
                    continue
                }
                throw ProviderFailure(provider: metadata.provider, statusCode: 0, code: "unreachable",
                    message: "The vendor could not be reached after retries. The existing request has not been resubmitted.",
                    accountBlocked: false, transient: true, acceptanceUnknown: false)
            }
        }
    }
}
