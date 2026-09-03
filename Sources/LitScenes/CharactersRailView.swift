import AppKit
import SwiftUI

/// The character rail: one card per character, the sheet as its face once cast, a
/// dashed frame while not. Drop images on a card to add source images.
struct CharactersRailView: View {
    let characters: [ProjectCharacter]
    let selectedCharacterId: String
    let sheetItem: (String) -> MediaItemRecord?
    let sheetOrdinal: (String) -> Int?
    let candidates: [MediaItemRecord]
    var onSelect: (String) -> Void
    var onCreate: (String) -> Void
    var onAppendSources: (String, [String]) -> Void
    var onDelete: (ProjectCharacter) -> Void

    private var castCount: Int {
        characters.filter { sheetItem($0.characterId) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CHARACTERS · \(characters.count)")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                if !characters.isEmpty {
                    Text("\(castCount) OF \(characters.count) CAST")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(castCount == characters.count ? CanonColor.brass.opacity(0.85) : CanonColor.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(characters) { character in
                        CharacterRailCard(
                            character: character,
                            sheet: sheetItem(character.characterId),
                            ordinal: sheetOrdinal(character.characterId),
                            candidates: candidates,
                            isSelected: character.characterId == selectedCharacterId,
                            onSelect: { onSelect(character.characterId) },
                            onDrop: { onAppendSources(character.characterId, $0) },
                            onDelete: { onDelete(character) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            RosterInlineCreateField(title: "New character", prompt: "Character name — Return creates") { name in
                onCreate(name)
            }
            .padding(10)
        }
        .background(CanonColor.sidebar)
    }
}

private struct CharacterRailCard: View {
    let character: ProjectCharacter
    let sheet: MediaItemRecord?
    let ordinal: Int?
    let candidates: [MediaItemRecord]
    let isSelected: Bool
    var onSelect: () -> Void
    var onDrop: ([String]) -> Void
    var onDelete: () -> Void

    @State private var isDropTargeted = false

    private var statusLine: String {
        if let ordinal, sheet != nil {
            return "CAST · \(characterSheetOrdinalLabel(ordinal))"
        }
        if sheet != nil { return "CAST" }
        return "NOT YET CAST · \(characterSourcesLabel(character.referenceMediaIds.count))"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                thumb
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name)
                        .font(CanonType.display(15, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(statusLine)
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(sheet == nil ? CanonColor.muted : CanonColor.brass.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTargeted ? CanonColor.softGold.opacity(0.14) : (isSelected ? CanonColor.archiveWell : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CanonColor.brass : (isDropTargeted ? CanonColor.brass.opacity(0.6) : CanonColor.hairlineDark), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
            let ids = payloads.map(\.mediaId)
            onDrop(ids)
            return !ids.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button("Delete Character…", role: .destructive, action: onDelete)
        }
        .help(sheet == nil ? "\(character.name) — not yet cast; drop images here to add source images" : "\(character.name) — cast")
    }

    private var leadSource: MediaItemRecord? {
        character.referenceMediaIds.lazy.compactMap { id in candidates.first { $0.mediaId == id } }.first
    }

    @ViewBuilder
    private var thumb: some View {
        if let sheet, let image = characterThumbnail(sheet) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 90)
                .background(CanonColor.mediaCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark))
        } else if let leadSource, let image = characterThumbnail(leadSource) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 90)
                .background(CanonColor.mediaCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(0.85)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(CanonColor.brass.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(CanonColor.brass.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: 60, height: 90)
                .overlay(
                    Text("NOT YET\nCAST")
                        .font(CanonType.archive(6.5, weight: .semibold))
                        .kerning(0.8)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CanonColor.muted)
                )
        }
    }
}
