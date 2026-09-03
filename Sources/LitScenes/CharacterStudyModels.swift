import Foundation

/// How a STUDIO study treats its reference images.
enum CharacterStudyLook: String, CaseIterable, Identifiable, Sendable {
    /// Keep the face and identity from the references; apply the written appearance.
    case asDescribed
    /// The same person with the same look, only the framing changes.
    case asPhotographed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asDescribed: return "AS DESCRIBED"
        case .asPhotographed: return "AS PHOTOGRAPHED"
        }
    }

    var help: String {
        switch self {
        case .asDescribed: return "Keep the face from the references and apply the written appearance"
        case .asPhotographed: return "Same person, same look — only the framing changes"
        }
    }

    fileprivate func promptClause(referenceCount: Int) -> String {
        let images = referenceCount == 1 ? "the attached reference image" : "the attached reference images"
        switch self {
        case .asDescribed:
            return "Use \(images) for the face and identity — this is the same person; apply the described appearance faithfully wherever it differs from the reference."
        case .asPhotographed:
            return "Match \(images) exactly — the same person with the same look, hair, and clothing — in the new framing."
        }
    }

    fileprivate func sourceDetail(name: String) -> String {
        switch self {
        case .asDescribed:
            return "CHARACTER identity reference for \"\(name)\": this is the same person; take the face, build, and distinguishing features from this image and apply the written appearance where it differs."
        case .asPhotographed:
            return "CHARACTER identity reference for \"\(name)\": render this exact person as photographed — same face, hair, and clothing — in the framing the written prompt asks for."
        }
    }
}

/// A reference the STUDIO offers a study render: a source image or the active sheet.
struct CharacterStudyReference: Hashable {
    var item: MediaItemRecord
    var label: String = ""
    var isSheet: Bool = false
}

/// One image a study render attaches, with the manifest detail it rides under.
struct CharacterStudyAttachment: Hashable {
    var mediaId: String
    var imagePath: String
    var label: String
    var detail: String
    var isSheet: Bool
}

/// THE STUDY RENDER LAW, extracted pure so it is testable while the engine's job
/// type stays private: the sheet (when offered) leads, then the chosen sources in
/// the operator's order, `capacity` images in all; a Stability stack folds several
/// into one composite; a text-only stack drops every reference — and says so.
struct CharacterStudyPlan: Hashable {
    var attachments: [CharacterStudyAttachment]
    var usesComposite: Bool
    /// References offered but not attached because the stack cannot take them.
    var droppedReferenceCount: Int

    var attachesReferences: Bool { !attachments.isEmpty }
}

enum CharacterStudyPrompt {
    /// The STUDIO's seed prompt: the roster study prompt (V1's exact composition)
    /// plus the LOOK clause when references ride.
    static func compose(
        name: String,
        description: String,
        signatureProps: [String],
        shot: RosterCharacterRenderPrompt.Shot,
        look: CharacterStudyLook,
        referenceCount: Int
    ) -> String {
        let base = RosterCharacterRenderPrompt.prompt(
            name: name,
            description: description,
            signatureProps: signatureProps,
            shot: shot
        )
        guard referenceCount > 0 else { return base }
        return base + "\n" + look.promptClause(referenceCount: referenceCount)
    }

    static func plan(
        name: String,
        references: [CharacterStudyReference],
        look: CharacterStudyLook,
        capacity: Int,
        isStability: Bool,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> CharacterStudyPlan {
        let subject = name.trimmed.isEmpty ? "the character" : name.trimmed
        let onDisk = references.filter { $0.item.kind == .image && fileExists($0.item.path) }
        let ordered = onDisk.filter(\.isSheet) + onDisk.filter { !$0.isSheet }
        guard capacity > 0 else {
            return CharacterStudyPlan(attachments: [], usesComposite: false, droppedReferenceCount: ordered.count)
        }
        var seen: Set<String> = []
        var attachments: [CharacterStudyAttachment] = []
        for reference in ordered {
            guard attachments.count < capacity, !seen.contains(reference.item.mediaId) else { continue }
            seen.insert(reference.item.mediaId)
            let detail = reference.isSheet
                ? RosterMentionResolver.characterStudyAttachmentDescriptor(
                    name: subject, label: "character sheet", isCompositeSheet: false, isCharacterSheet: true
                )
                : look.sourceDetail(name: subject) + labelSentence(reference.label)
            attachments.append(CharacterStudyAttachment(
                mediaId: reference.item.mediaId,
                imagePath: reference.item.path,
                label: reference.isSheet ? "\(subject) — reference sheet" : subject,
                detail: detail,
                isSheet: reference.isSheet
            ))
        }
        return CharacterStudyPlan(
            attachments: attachments,
            usesComposite: isStability && attachments.count > 1,
            droppedReferenceCount: ordered.count - attachments.count
        )
    }

    private static func labelSentence(_ label: String) -> String {
        let trimmed = label.trimmed
        return trimmed.isEmpty ? "" : " This particular reference shows: \(trimmed)."
    }
}

/// What the STUDIO asks a study render to attach: media ids (source images and/or
/// the active sheet) and how to treat them.
struct CharacterStudyReferences: Hashable, Sendable {
    var mediaIds: [String]
    var look: CharacterStudyLook
}
