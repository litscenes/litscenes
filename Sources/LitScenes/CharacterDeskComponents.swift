import AppKit
import SwiftUI

/// Small pieces the CHARACTERS tab shares: the tone palette, the brass caps text
/// button, the section header, and the thumbnail lookup that never decodes in `body`.
func castingToneColor(_ tone: CharacterCastingTone) -> Color {
    switch tone {
    case .muted: return CanonColor.muted
    case .brass: return CanonColor.brass
    case .softGold: return CanonColor.softGold
    case .rust: return CanonColor.rust
    }
}

/// A brass caps text button — the tab's quiet action voice.
struct CharacterCapsButton: View {
    let title: String
    var color: Color = CanonColor.brass
    var size: CGFloat = 8
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.archive(size, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }
}

/// An eyebrow with a hairline rule; trailing content sits at the right edge.
struct CharacterSectionHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(count.map { "\(title) · \($0)" } ?? title)
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
                .layoutPriority(1)
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            trailing()
        }
    }
}

/// Cached thumbnail for a media item; nil when the file is gone.
func characterThumbnail(_ item: MediaItemRecord, maxPixel: Int = 240) -> NSImage? {
    StripThumbnailCache.shared.image(path: item.thumbnailPath.isEmpty ? item.path : item.thumbnailPath, maxPixel: maxPixel)
}

/// A capsule chip in the dark room: brass when active, hairline when not.
struct CharacterChip: View {
    let title: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.archive(8, weight: isActive ? .bold : .semibold))
                .kerning(0.8)
                .lineLimit(1)
                .foregroundStyle(isActive ? CanonColor.ink : (isDisabled ? CanonColor.muted.opacity(0.6) : CanonColor.bone.opacity(0.82)))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(isActive ? CanonColor.brass : Color.clear))
                .overlay(Capsule().stroke(isActive ? Color.clear : CanonColor.hairlineDark, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(isDisabled)
        .help(help)
    }
}

/// The per-character render stack picker: a ghost capsule menu. AppKit menu items
/// take no glyphs, so a stack's state rides as a text suffix.
struct CharacterStackMenu: View {
    let stacks: [RenderStack]
    let selectedStack: RenderStack?
    let credentialBlocker: (RenderStack) -> String?
    /// On the cream plate the capsule takes the plate's ink and hairline.
    var onPlate: Bool = false
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(stacks) { stack in
                Button {
                    onSelect(stack.id)
                } label: {
                    Text(
                        characterStackMenuLabel(
                            label: stack.label,
                            isTextOnly: !stack.reframeCapable,
                            blocked: credentialBlocker(stack) != nil
                        ) + (stack.id == selectedStack?.id ? " ✓" : "")
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let selectedStack, credentialBlocker(selectedStack) != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .semibold))
                }
                Text(selectedStack?.label ?? "No stack")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(0.8)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(onPlate ? PlateColor.ink.opacity(0.75) : CanonColor.bone.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay(Capsule().stroke(onPlate ? PlateColor.hairline : CanonColor.hairlineDark, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("The render stack for this character's sheet and studies")
    }
}
