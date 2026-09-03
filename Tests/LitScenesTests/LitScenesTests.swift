import Foundation
import Testing
@testable import LitScenes

@Test
func normalizerGeneratesIdsFromDraftWithoutTrustingModelIds() throws {
    let draft = ScreenGraphHydrationDraft(
        schemaVersion: ScreenGraphConstants.draftSchemaVersion,
        observationGoal: "Understand a product website.",
        subject: DraftObservedSubjectProfile(
            scope: .business,
            canonicalName: "Acme Studio",
            aliases: [],
            oneLineIdentity: "A design studio.",
            domains: ["design"],
            visibleOfferings: ["brand systems"],
            visibleAudiences: ["founders"],
            peopleOrRoles: [],
            places: [],
            channels: ["website"],
            visualIdentitySignals: ["minimal black and white UI"],
            voiceToneSignals: ["direct"],
            evidenceIndices: [0]
        ),
        surfaces: [
            DraftObservedScreenSurface(
                kind: .website,
                appOrSite: "Safari",
                titleOrUrl: "https://example.com",
                captureRef: "",
                visibleTextSummary: "Acme Studio homepage",
                literalVisualSummary: "A website hero and navigation.",
                piiRisk: .none,
                redactionNotes: [],
                confidence0To1: 0.9
            )
        ],
        evidence: [
            DraftScreenEvidence(
                surfaceIndex: 0,
                kind: .onScreenText,
                quoteOrSummary: "Acme Studio",
                whereSeen: "hero",
                confidence0To1: 0.95
            )
        ],
        claims: [
            DraftKnowledgeClaim(
                claim: "The business presents brand systems as a core offering.",
                status: .observed,
                evidenceIndices: [0],
                confidence0To1: 0.85
            )
        ],
        northStarSignals: NorthStarSignals(
            literallyShowing: ["website homepage"],
            impliedArchetypalSituations: [],
            activeSymbols: [],
            valueTensions: [],
            expressedThoughts: [],
            supportedThemes: [],
            transformationPotential: [],
            likelyBeatFunctions: [],
            negativeConstraints: []
        ),
        seedNodes: [
            DraftScreenGraphSeedNode(
                kind: .meaningClaim,
                abstractionLevel: .literal,
                name: "Brand systems offering",
                definition: "",
                meaningClaim: "Brand systems are a visible offering.",
                positiveExpression: "",
                negativeExpression: "",
                boundary: "",
                aliases: [],
                tags: ["business"],
                evidenceIndices: [0],
                confidenceScore: 0.8,
                reuseScore: 0.7,
                reviewNote: ""
            )
        ],
        seedEdges: [],
        openQuestionsForUser: [],
        uncertaintyNotes: [],
        privacyWarnings: [],
        operatorSummary: "The screen shows Acme Studio's website."
    )

    let context = ScreenGraphNormalizer(
        sessionId: "session_test",
        captureId: "cap_test",
        captureRef: "captures/cap_test.png",
        observedAt: "2026-05-28T00:00:00Z",
        model: "gpt-5.5"
    ).normalize(draft)

    #expect(context.surfaces.count == 1)
    #expect(context.surfaces[0].surfaceId.hasPrefix("surface_"))
    #expect(context.evidence[0].evidenceId.hasPrefix("evidence_"))
    #expect(context.claims[0].evidenceIds == [context.evidence[0].evidenceId])
    #expect(context.seedNodes[0].evidenceIds == [context.evidence[0].evidenceId])
}

@Test
func costEstimatorUsesCachedInputDiscount() throws {
    let manifest = PricingManifest(
        schemaVersion: "test",
        updatedAt: "today",
        source: "test",
        models: [
            ModelPricing(model: "gpt-test", inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 20)
        ]
    )
    let estimator = CostEstimator(manifest: manifest)
    let usage = OpenAIUsage(
        inputTokens: 1_000_000,
        outputTokens: 500_000,
        totalTokens: 1_500_000,
        inputTokensDetails: OpenAIInputTokensDetails(cachedTokens: 200_000),
        outputTokensDetails: nil
    )

    #expect(abs(estimator.actualCost(model: "gpt-test", usage: usage) - 18.2) < 0.0001)
}

@Test
func diffEngineSkipsExactDuplicate() {
    let engine = DiffEngine()
    let signature = FrameSignature(sha256: "abc", perceptualHash: 0xff, ocrFingerprint: "txt")
    let decision = engine.decide(
        current: signature,
        previousAnalyzed: signature,
        secondsSinceLastAnalysis: 1,
        heartbeatSeconds: 30
    )
    #expect(decision.shouldAnalyze == false)
    #expect(decision.kind == .exactDuplicate)
}

@Test
func diffEngineVisualGateIgnoresOcrOnlyChanges() {
    let engine = DiffEngine()
    let previous = FrameSignature(sha256: "abc", perceptualHash: 0xff, ocrFingerprint: "old-text")
    let current = FrameSignature(sha256: "def", perceptualHash: 0xff, ocrFingerprint: "new-text")
    let decision = engine.decideVisualOnly(
        current: current,
        previousAnalyzed: previous,
        secondsSinceLastAnalysis: 2,
        heartbeatSeconds: 45
    )

    #expect(decision.shouldAnalyze == false)
    #expect(decision.kind == .cursorOnlyOrTinyChange)
}

@Test
func projectIdUsesTimestampSlugAndUuid() throws {
    let date = Date(timeIntervalSince1970: 0)
    let uuid = try #require(UUID(uuidString: "12345678-1234-1234-1234-123456789abc"))
    let projectId = ProjectLibrary.projectId(for: "Client Website Audit", date: date, uuid: uuid)

    #expect(projectId == "project_19700101T000000_client-website-audit_12345678")
}

@Test
func projectSessionsAreNestedUnderProjectDirectory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_project_test_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = ProjectLibrary(root: root)
    let project = try library.createProject(named: "Client Site")
    let store = ArtifactStore(project: project, sessionId: "session_test", library: library)
    try store.prepare(config: SessionConfig())
    let updated = try library.recordSessionStarted(project: project, sessionId: "session_test")
    let listed = try library.listProjects()

    #expect(store.sessionDir.path.hasSuffix("\(project.projectId)/sessions/session_test"))
    #expect(FileManager.default.fileExists(atPath: store.sessionJson.path))
    #expect(updated.sessionCount == 1)
    #expect(updated.lastSessionId == "session_test")
    #expect(listed.first?.projectId == project.projectId)

    let sessionData = try Data(contentsOf: store.sessionJson)
    let sessionJSON = try #require(JSONSerialization.jsonObject(with: sessionData) as? [String: String])
    #expect(sessionJSON["project_id"] == project.projectId)
    #expect(sessionJSON["project_name"] == "Client Site")
}
