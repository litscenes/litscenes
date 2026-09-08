import SwiftUI

func scenesV2PlannedReferenceMarks(
    planned: ProjectLensHeroImage,
    lens: ProjectLens,
    stack: RenderStack,
    entries: [RosterMentionResolver.Entry],
    items: [MediaItemRecord],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ScenesV2CastMark] {
    let resolved = LensPlannedFrameDefaults.entries(planned: planned, lens: lens, available: entries)
    let plan = LensPlannedFrameDefaults.referencePlan(planned: planned, lens: lens, stack: stack, available: entries, items: items, fileExists: fileExists)
    var marks = resolved.filter { $0.kind == .character }.map { entry in
        let requested = LensPlannedFrameDefaults.mentionAttachments(for: [entry], items: items, fileExists: fileExists)
        let riding = requested.filter { reference in plan.attachments.contains { $0.sourceId == reference.sourceId } }
        let first = riding.first
        let sheet = first.flatMap { reference in items.first { $0.mediaId == reference.sourceId } }
        let isSheet = sheet.map { $0.isCharacterSheet || $0.isRosterCompositeSheet } ?? false
        let summary: String
        if requested.isEmpty {
            summary = "\(entry.name): no readable references · text only"
        } else if riding.isEmpty {
            summary = "\(entry.name): references omitted by \(stack.label) · text only"
        } else {
            let kind = isSheet ? "reference sheet" : "\(riding.count) source photo\(riding.count == 1 ? "" : "s")"
            let omitted = requested.count - riding.count
            summary = "\(entry.name): \(kind) attached" + (omitted > 0 ? " · \(omitted) omitted" : "")
        }
        return ScenesV2CastMark(
            name: entry.name, hasSheet: isSheet, avatarImagePath: first?.imagePath ?? "",
            avatarIsSheet: isSheet, hasSources: !riding.isEmpty && !isSheet, referenceSummary: summary
        )
    }
    let linkedIds = Set([planned.characterId, planned.suggestedForCharacterId ?? ""].filter { !$0.isEmpty })
    if linkedIds.contains(where: { id in !resolved.contains { $0.kind == .character && $0.id == id } }) {
        marks.append(ScenesV2CastMark(name: "Linked character", hasSheet: false, referenceSummary: "Linked character unavailable · text only"))
    }
    return marks
}

struct ScenesV2ReferenceSummary: View {
    let marks: [ScenesV2CastMark]
    var onRepair: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                HStack(spacing: 6) {
                    if !mark.avatarImagePath.isEmpty,
                       let image = StripThumbnailCache.shared.image(path: mark.avatarImagePath, maxPixel: 80) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    }
                    Text(mark.referenceSummary)
                        .font(CanonType.interface(9.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(mark.hasSheet || mark.hasSources ? CanonColor.muted : CanonColor.rust)
            }
            if marks.contains(where: { !$0.hasSheet && !$0.hasSources }) {
                Button("Review character references", action: onRepair)
                    .buttonStyle(.plain)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
            }
        }
    }
}
