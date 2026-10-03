import AppKit
import CryptoKit
import Foundation

struct ShotCharacterReferenceImage: Codable, Hashable, Sendable {
    var mediaId: String
    var path: String
    var fingerprint: String

    @MainActor private static var previewCache: [String: Self] = [:]

    @MainActor static func preview(mediaId: String, path: String) -> Self? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return nil }
        let key = "\(mediaId):\(path):\(modified.timeIntervalSince1970):\(size)"
        if let cached = previewCache[key] { return cached }
        guard let image = read(mediaId: mediaId, path: path) else { return nil }
        if previewCache.count > 256 { previewCache.removeAll() }
        previewCache[key] = image
        return image
    }

    static func read(mediaId: String, path: String) -> Self? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              data.count <= 50 * 1024 * 1024,
              let size = imagePixelSize(from: data), size.width >= 300, size.height >= 300,
              (0.4...2.5).contains(Double(size.width) / Double(size.height)) else { return nil }
        return Self(mediaId: mediaId, path: path,
            fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

struct ShotCharacterReference: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var aliases: [String]
    /// Frontal identity anchor followed by one to three distinct source views.
    var images: [ShotCharacterReferenceImage]
    var entry: RosterMentionResolver.Entry {
        RosterMentionResolver.Entry(id: id, name: name, kind: .character, aliases: aliases)
    }
    var isUsable: Bool {
        (2...4).contains(images.count) && Set(images.map(\.fingerprint)).count == images.count
    }
}

struct ShotContinuationReferenceRecipe: Codable, Hashable, Sendable {
    var characters: [ShotCharacterReference]
    var usesImages: Bool

    func providerPrompt(_ prompt: String) -> String {
        let resolution = RosterMentionResolver.resolve(prompt: prompt, entries: characters.map(\.entry))
        let active = characters.filter { reference in resolution.mentions.contains { $0.id == reference.id } }
        let replacements = Dictionary(uniqueKeysWithValues: active.enumerated().map {
            ($0.element.id, usesImages ? "@Element\($0.offset + 1)" : $0.element.name)
        })
        return RosterMentionResolver.resolve(prompt: prompt, entries: characters.map(\.entry), replacementNames: replacements).cleanedPrompt
    }

    func activeCharacters(prompt: String) -> [ShotCharacterReference] {
        let ids = Set(RosterMentionResolver.resolve(prompt: prompt, entries: characters.map(\.entry)).mentions.map(\.id))
        return characters.filter { ids.contains($0.id) }
    }

    func validated(model: VideoModelSelection, personal: Bool, prompt: String) throws -> [ShotCharacterReference] {
        guard usesImages else { return [] }
        let active = activeCharacters(prompt: prompt)
        guard active.isEmpty || (model == .falKlingV3ProImageToVideo && personal) else {
            throw ScreenGraphError.capture("Character images require Kling 3 Pro with your personal FAL account. Review the model and price.")
        }
        for character in active {
            guard character.isUsable,
                  character.images.allSatisfy({ ShotCharacterReferenceImage.read(mediaId: $0.mediaId, path: $0.path)?.fingerprint == $0.fingerprint }) else {
                throw ScreenGraphError.capture("Character references changed or are unavailable. Review references or explicitly continue without images.")
            }
        }
        return active
    }

    var traceSummary: [[String: Any]] {
        characters.enumerated().map { index, character in
            ["character_id": character.id, "name": character.name, "element": index + 1,
             "uses_images": usesImages,
             "images": character.images.map { ["media_id": $0.mediaId, "sha256": $0.fingerprint] }] as [String: Any]
        }
    }
}

extension LibraryEngine {
    var continuationCharacterReferences: [ShotCharacterReference] {
        frameCreatorMentionEntries(for: nil).filter { $0.kind == .character }.map { entry in
            var seen = Set<String>()
            let ids = [entry.activeSheetMediaId] + entry.referenceMediaIds
            let images = ids.compactMap { id -> ShotCharacterReferenceImage? in
                guard let media = browsableMediaItems.first(where: { $0.mediaId == id }), media.kind == .image,
                      let image = ShotCharacterReferenceImage.preview(mediaId: id, path: media.path),
                      seen.insert(image.fingerprint).inserted else { return nil }
                return image
            }
            return ShotCharacterReference(id: entry.id, name: entry.name, aliases: entry.aliases, images: Array(images.prefix(4)))
        }
    }
}
