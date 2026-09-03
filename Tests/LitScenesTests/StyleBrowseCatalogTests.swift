import Foundation
import Testing
@testable import LitScenes

private final class CatalogOfflineURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct StyleBrowseCatalogTests {
    @Test
    func releaseIdentitiesAreDistinctAndCommunityIsAGPLOnly() {
        let development = LitScenesReleaseIdentity.resolve(channelValue: "development")
        let community = LitScenesReleaseIdentity.resolve(
            channelValue: "community-release",
            sourceURLString: "https://github.com/litscenes/litscenes/tree/abc123",
            sourceRevision: "abc123"
        )
        let official = LitScenesReleaseIdentity.resolve(
            channelValue: "official-commercial-release",
            bundleIdentifier: "ai.litscenes.official"
        )

        #expect(development.bundleIdentifier == "ai.litscenes.development")
        #expect(community.bundleIdentifier == "ai.litscenes.community")
        #expect(official.bundleIdentifier == "ai.litscenes.official")
        #expect(Set([development.applicationSupportDirectoryName, community.applicationSupportDirectoryName, official.applicationSupportDirectoryName]).count == 3)
        #expect(community.licenseLabel == "AGPL-3.0-only")
        #expect(community.correspondingSourceURL?.absoluteString.hasSuffix("/tree/abc123") == true)
        #expect(!community.usesOfficialBranding)
        #expect(official.usesOfficialBranding)
    }

    @Test
    func catalogPayloadIntegrityRejectsChangedBytesAndSizes() {
        let data = Data("catalog".utf8)
        let hash = sha256Hex(data)

        #expect(CatalogPayloadIntegrity.matches(data, sha256: hash, byteSize: data.count))
        #expect(!CatalogPayloadIntegrity.matches(Data("changed".utf8), sha256: hash, byteSize: data.count))
        #expect(!CatalogPayloadIntegrity.matches(data, sha256: hash, byteSize: data.count + 1))
    }

    @Test
    func manifestRequiresExactNormalizedCatalogURLsAndUniqueEntries() async throws {
        let validHash = String(repeating: "a", count: 64)
        let terms = CatalogManifestFile(
            kind: "terms",
            path: "v1/terms/2026-08-11.md",
            url: "https://catalog.litscenes.ai/v1/terms/2026-08-11.md",
            sha256: validHash,
            byteSize: 100
        )
        let browse = CatalogManifestFile(
            kind: "style_browse",
            path: "v1/catalogs/browse.json",
            url: "https://catalog.litscenes.ai/v1/catalogs/browse.json",
            sha256: validHash,
            byteSize: 100
        )
        let reference = CatalogManifestFile(
            kind: "style_reference",
            path: "v1/catalogs/reference.json",
            url: "https://catalog.litscenes.ai/v1/catalogs/reference.json",
            sha256: validHash,
            byteSize: 100
        )
        let runtime = CatalogManifestRuntime(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("manifest-validation-\(UUID().uuidString)")
        )
        let valid = CatalogManifest(
            schemaVersion: CatalogManifest.schemaVersion,
            manifestVersion: "v1",
            publishedAt: "2026-08-13T02:34:11Z",
            termsSha256: validHash,
            terms: terms,
            catalogs: [browse, reference],
            compatibility: CatalogManifestCompatibility(
                minimumDesktopVersion: "0.1.0",
                clientFamilies: ["LitScenes Desktop"]
            )
        )
        try await runtime.validateManifest(valid)

        var mismatchedURL = valid
        mismatchedURL.catalogs[0].url = "https://catalog.litscenes.ai/v1/catalogs/other.json"
        await #expect(throws: Error.self) { try await runtime.validateManifest(mismatchedURL) }

        var credentialedURL = valid
        credentialedURL.catalogs[0].url = "https://user@catalog.litscenes.ai/v1/catalogs/browse.json"
        await #expect(throws: Error.self) { try await runtime.validateManifest(credentialedURL) }

        var duplicatePath = valid
        duplicatePath.catalogs[1].path = duplicatePath.catalogs[0].path
        duplicatePath.catalogs[1].url = duplicatePath.catalogs[0].url
        await #expect(throws: Error.self) { try await runtime.validateManifest(duplicatePath) }
    }

    @Test
    func offlineCatalogUsesBundledThenDurableLastKnownGood() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogOfflineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes-catalog-test-\(UUID().uuidString)", isDirectory: true)

        let firstRuntime = CatalogManifestRuntime(session: session, rootURL: root)
        let bundled = try await firstRuntime.loadSnapshot()
        #expect(bundled.origin == .bundled)
        #expect(bundled.styleBrowse.isUsable)
        #expect(bundled.styleReference.isUsable)
        #expect(!bundled.warning.isEmpty)

        let secondRuntime = CatalogManifestRuntime(session: session, rootURL: root)
        let cached = try await secondRuntime.loadSnapshot()
        #expect(cached.origin == .cached)
        #expect(cached.manifest.manifestVersion == bundled.manifest.manifestVersion)
        #expect(cached.terms.contains("visible notice"))
        #expect(!cached.warning.isEmpty)
    }

    @Test
    func decodesPublishedCatalogContract() throws {
        let json = """
        {
         "schema_version": "litscenes.style_browse_catalog.v0.1",
         "catalog_kind": "style_browse_catalog",
         "version": "v20260702T010428Z",
         "generated_at": "2026-07-02T01:04:28+00:00",
         "taxonomy_version": "v1",
         "categorization_model": "gpt-5.5",
         "style_count": 1,
         "collections": [
          {
           "key": "anime",
           "name": "Anime & Cel",
           "description": "Anime/manga-register rendering.",
           "dot_color_hex": "#e06a6a",
           "sort_order": 20
          }
         ],
         "styles": [
          {
           "id": "07ac09f9-25fa-4232-a52a-303f9c1aed2a",
           "title": "Vibrant Anime",
           "label": "Vermilion Teal Anime Noir",
           "caption": "Bold anime-graphic illustration.",
           "url": "https://example.cloudfront.net/page-01_card-001.png",
           "collection": "anime",
           "secondary_collection": "nocturne",
           "moods": ["Energetic", "Mysterious", "Elegant"],
           "hue_name": "Crimson",
           "hue_hex": "#c0392b",
           "medium": "Digital painting",
           "sat": 5,
           "con": 4,
           "ser": 3,
           "lin": 4,
           "sty": 3,
           "sref_code": "2244696458",
           "page": 1,
           "card_index": 1
          }
         ]
        }
        """
        let catalog = try JSONCoding.decoder.decode(StyleBrowseCatalog.self, from: Data(json.utf8))
        #expect(catalog.isUsable)
        #expect(catalog.displayCollections.first?.key == "anime")
        #expect(catalog.styles.first?.secondaryCollection == "nocturne")
        #expect(catalog.styles.first?.hueHex == "#c0392b")
        #expect(catalog.styles.first?.moods.count == 3)
        #expect(catalog.style(withId: "07ac09f9-25fa-4232-a52a-303f9c1aed2a")?.displayLabel == "Vermilion Teal Anime Noir")
    }

    @Test
    func lensBodyWithoutStyleTreatmentStillDecodes() throws {
        var body = LensBody.empty()
        body.title = "Test Lens"
        var encoded = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(body)) as? [String: Any]
        encoded?.removeValue(forKey: "styleTreatment")
        let data = try JSONSerialization.data(withJSONObject: encoded ?? [:])
        let decoded = try JSONCoding.decoder.decode(LensBody.self, from: data)
        #expect(decoded.title == "Test Lens")
        #expect(decoded.styleTreatment == nil)
    }

    @Test
    func styleTreatmentNormalizationEnforcesTreatmentRules() {
        let primary = LensStyleTreatmentSlot(styleId: "style-a", label: "Primary", weight: 200)
        let duplicateAccent = LensStyleTreatmentSlot(styleId: "style-a", label: "Duplicate", weight: 25)
        let accentOne = LensStyleTreatmentSlot(styleId: "style-b", label: "Accent 1", weight: 1)
        let accentTwo = LensStyleTreatmentSlot(styleId: "style-c", label: "Accent 2", weight: 15)
        let accentThree = LensStyleTreatmentSlot(styleId: "style-d", label: "Accent 3", weight: 10)
        let treatment = LensStyleTreatment(
            catalogVersion: " v20260702T010428Z ",
            primary: primary,
            accents: [duplicateAccent, accentOne, accentTwo, accentThree]
        ).normalized()

        #expect(treatment.catalogVersion == "v20260702T010428Z")
        #expect(treatment.primary?.weight == 90)
        #expect(treatment.accents.map(\.styleId) == ["style-b", "style-c"])
        #expect(treatment.accents.first?.weight == 5)
        #expect(treatment.slots.count == 3)
        #expect(!treatment.recipeText.isEmpty)

        let cleared = LensStyleTreatment(primary: nil, accents: []).normalized()
        #expect(cleared.isEmpty)
    }

    @Test
    func lensBodyRoundTripsStyleTreatment() throws {
        var body = LensBody.empty()
        body.styleTreatment = LensStyleTreatment(
            catalogVersion: "v20260702T010428Z",
            primary: LensStyleTreatmentSlot(styleId: "style-a", label: "Primary", weight: 60),
            accents: [LensStyleTreatmentSlot(styleId: "style-b", label: "Accent", weight: 25)]
        )
        let decoded = try JSONCoding.decoder.decode(LensBody.self, from: JSONCoding.encoder.encode(body))
        #expect(decoded.styleTreatment?.primary?.styleId == "style-a")
        #expect(decoded.styleTreatment?.accents.count == 1)
        #expect(decoded.normalized().styleTreatment?.isEmpty == false)
    }
}
