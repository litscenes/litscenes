import SwiftUI

// Shared roster thumbnail helpers, used by the project roster sheet and the sidebar's
// identity group headers. (Casting is implicit — a character is in a scene when they
// have a take there — so there is no separate cast-editing surface.)

/// A media item's thumbnail (or source image) filled into a rounded square.
func mediaItemThumbnail(_ item: MediaItemRecord, side: CGFloat) -> some View {
    Color.clear
        .overlay(
            Group {
                if let nsImage = NSImage(contentsOfFile: item.thumbnailPath.isEmpty ? item.path : item.thumbnailPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    CanonColor.paperInset
                }
            }
        )
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
}

/// A roster entry's face: its leading resolvable reference image, or an initial-letter
/// circle when it has none.
func rosterBucketThumbnail(name: String, referenceMediaIds: [String], candidates: [MediaItemRecord], side: CGFloat) -> some View {
    Group {
        if let item = referenceMediaIds.lazy.compactMap({ mediaId in candidates.first { $0.mediaId == mediaId } }).first {
            mediaItemThumbnail(item, side: side)
        } else {
            Circle()
                .fill(CanonColor.paperInset)
                .frame(width: side, height: side)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(CanonType.editorial(side * 0.45, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                )
        }
    }
}
