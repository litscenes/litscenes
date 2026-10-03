import AppKit
import Foundation
import SQLite3
import Testing
@testable import LitScenes

/// A documentary counter-fixture: the compiler depends on roster identity,
/// never the people, setting or genre that motivated the mention UI.
@Test func continuationReferenceCompilerSurvivesRenamedDocumentaryCast() throws {
    let diver = ShotCharacterReference(id: "cast_a", name: "Survey Diver", aliases: ["Field Researcher"], images: [])
    let pilot = ShotCharacterReference(id: "cast_b", name: "Submersible Pilot", aliases: [], images: [])
    let recipe = ShotContinuationReferenceRecipe(characters: [diver, pilot], usesImages: true)
    let prompt = "@Field Researcher signals to @Submersible Pilot; @Survey Diver turns."
    #expect(recipe.providerPrompt(prompt) == "@Element1 signals to @Element2; @Element1 turns.")
    let renamed = ShotContinuationReferenceRecipe(characters: [
        ShotCharacterReference(id: "cast_a", name: "Orchard Worker", aliases: [], images: []),
        ShotCharacterReference(id: "cast_b", name: "Harvest Driver", aliases: [], images: [])
    ], usesImages: true)
    #expect(renamed.providerPrompt("@Orchard Worker signals to @Harvest Driver; @Orchard Worker turns.") == recipe.providerPrompt(prompt))
    var textOnly = recipe
    textOnly.usesImages = false
    #expect(textOnly.providerPrompt(prompt) == "Survey Diver signals to Submersible Pilot; Survey Diver turns.")
    #expect(try textOnly.validated(model: .falWan27ImageToVideo, personal: false, prompt: prompt).isEmpty)
    #expect(throws: (any Error).self) { try recipe.validated(model: .falWan27ImageToVideo, personal: true, prompt: prompt) }
    #expect(throws: (any Error).self) { try recipe.validated(model: .falKlingV3ProImageToVideo, personal: false, prompt: prompt) }
    #expect(throws: (any Error).self) { try recipe.validated(model: .falKlingV3ProImageToVideo, personal: true, prompt: prompt) }

    var take = ShotContinuationTake(prompt: prompt)
    take.referenceRecipe = recipe
    take.providerPrompt = recipe.providerPrompt(prompt)
    let reloaded = try JSONDecoder().decode(ShotContinuationTake.self, from: JSONEncoder().encode(take))
    #expect(reloaded.referenceRecipe == recipe)
    #expect(reloaded.providerPrompt == take.providerPrompt)
    #expect(try JSONDecoder().decode(ShotContinuationTake.self, from: Data("{}".utf8)).referenceRecipe == nil)
}

@Test func continuationReferenceTracePersistsSafePromptAndArtifactProvenance() async throws {
    let id = UUID().uuidString
    let image = ShotCharacterReferenceImage(mediaId: "source_front", path: "/private/unused/reference.png", fingerprint: "safe-content-hash")
    let recipe = ShotContinuationReferenceRecipe(characters: [
        ShotCharacterReference(id: "documentary_cast", name: "Survey Diver", aliases: [], images: [image])
    ], usesImages: true)
    var take = ShotContinuationTake(takeId: id, prompt: "@Survey Diver explores the reef.", stack: ShotRenderStack.fallback.replacingModel(.falKlingV3Pro).rawValue)
    take.referenceRecipe = recipe
    take.providerPrompt = recipe.providerPrompt(take.prompt)
    for status in ["start", "success", "error", "canceled"] {
        await recordShotContinuationEvent(take: take, projectId: "reference-counter-fixture", shotId: id,
            phase: "offline_validation", status: status, message: "Offline validation; no provider request")
    }
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(InferenceTraceSettings.databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "SELECT request_text_json, media_refs_json, trace_id FROM inference_calls WHERE artifact_id = ?", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    var count = 0
    var traceIds: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let prompt = String(cString: sqlite3_column_text(statement, 0))
        let media = String(cString: sqlite3_column_text(statement, 1))
        #expect(prompt.contains("@Element1"))
        #expect(prompt.contains("@Survey Diver"))
        #expect(media.contains("safe-content-hash"))
        #expect(!media.contains("/private/unused"))
        traceIds.append(String(cString: sqlite3_column_text(statement, 2)))
        count += 1
    }
    #expect(count == 4)
    let records = try await InferenceTraceStore.shared.workflowTraceRecords(ids: traceIds)
    #expect(records.count == 4)
    #expect(records.allSatisfy { $0.rawJSON.contains("@Element1") && $0.rawJSON.contains("safe-content-hash") })
}

private actor ReferenceWireCapture {
    var body: Data?
    func save(_ data: Data) { body = data }
}

private final class ReferenceWireProtocol: URLProtocol, @unchecked Sendable {
    static let capture = ReferenceWireCapture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
        }
        let captured = data
        Task {
            await Self.capture.save(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"detail\":\"Offline reference fixture; no generation\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private struct ReferenceWireCredentials: LitScenesCredentialResolving {
    func resolvedCredential(for provider: LitScenesProviderCredential) -> String { "offline-fixture" }
    func resolvedCredentialValue(forKey key: String) -> String { "offline-fixture" }
    func resolvedCredentialValue(forKeys keys: [String]) -> String { "offline-fixture" }
    func credentialStatus(for provider: LitScenesProviderCredential) -> CredentialStatus {
        .init(provider: provider, source: .environment, isConfigured: true, message: "Offline fixture")
    }
    func lensContextCredentialStatus(for credential: LensContextCredential) -> LensContextCredentialStatus {
        .init(credential: credential, source: .missing, isConfigured: false, message: "Offline fixture")
    }
}

@MainActor @Test func continuationReferencesReachWireWithoutChangingAnchorOrLeakingImagesIntoTrace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reference-wire-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var references: [ShotCharacterReferenceImage] = []
    for index in 0..<2 {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 900, bitsPerPixel: 24))
        memset(bitmap.bitmapData, Int32(50 + index * 100), bitmap.bytesPerRow * bitmap.pixelsHigh)
        let url = directory.appendingPathComponent("view-\(index).png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        references.append(try #require(ShotCharacterReferenceImage.read(mediaId: "source_\(index)", path: url.path)))
    }
    let reference = ShotCharacterReference(id: "survey_cast", name: "Survey Diver", aliases: [], images: references)
    let recipe = ShotContinuationReferenceRecipe(characters: [reference], usesImages: true)
    let prompt = "@Survey Diver studies the reef."
    let runId = UUID().uuidString
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReferenceWireProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    await ProviderBilling.$snapshot.withValue(.init(defaultSource: .personal, overrides: [:])) {
        await TracedHTTPTransport.$session.withValue(session) {
            do {
                _ = try await FALVideoClient(credentialStore: ReferenceWireCredentials()).generateImageToVideo(from:
                    FALImageToVideoRequest(projectId: "reference-counter-fixture", runId: runId, traceGroupId: runId,
                        workflowName: "shot_continuation", artifactType: "shot_continuation_take", artifactId: runId,
                        modelSelection: .falKlingV3ProImageToVideo, prompt: recipe.providerPrompt(prompt), negativePrompt: "",
                        durationSeconds: 5, generateAudio: false, outputProfile: .standard(.landscape16x9),
                        startFrameURL: URL(fileURLWithPath: references[0].path), targetEndFrameURL: nil,
                        outputURL: directory.appendingPathComponent("unused.mp4"), characterReferences: [reference], operatorPrompt: prompt))
                Issue.record("The offline provider must refuse generation")
            } catch { }
        }
    }
    let body = try #require(await ReferenceWireProtocol.capture.body)
    let wire = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(wire["prompt"] as? String == "@Element1 studies the reef.")
    let elements = try #require(wire["elements"] as? [[String: Any]])
    #expect(elements.count == 1)
    #expect((elements[0]["reference_image_urls"] as? [String])?.count == 1)
    #expect(elements[0]["frontal_image_url"] as? String == wire["start_image_url"] as? String)
    #expect(wire["operator_prompt"] == nil)
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(InferenceTraceSettings.databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "SELECT trace_id FROM inference_calls WHERE artifact_id = ?", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    _ = runId.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    var ids: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW { ids.append(String(cString: sqlite3_column_text(statement, 0))) }
    let traces = try await InferenceTraceStore.shared.workflowTraceRecords(ids: ids)
    #expect(!traces.isEmpty)
    let raw = traces.map(\.rawJSON).joined()
    #expect(raw.contains("@Element1") && raw.contains("@Survey Diver") && raw.contains("422"))
    #expect(raw.contains(references[1].fingerprint))
    #expect(!raw.contains("base64,"))
}
