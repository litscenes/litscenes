import SwiftUI

/// THE CANON SCROLLER — the app's own horizontal scrollbar for canvas
/// surfaces, replacing the stock macOS overlay bar (a foreign white slab on
/// the dark canon). Wraps its content in a `ScrollView(.horizontal)` with
/// native indicators hidden and draws its own track underneath: a hairline
/// with a brass thumb — present exactly while the content overflows (mouse
/// users have no swipe), hover-thickened, draggable, and click-to-jump.
/// Trackpad/wheel scrolling is untouched, and a `ScrollViewReader` wrapping
/// this view can still drive `scrollTo(id:)` anchors.
struct CanonHScroller<Content: View>: View {
    /// Horizontal inset for the track only (align it with padded content).
    var trackInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @State private var position = ScrollPosition()
    @State private var offsetX: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var isDragging = false
    /// The grab point inside the thumb, set on the first drag change so the
    /// thumb never jumps under the cursor mid-grab.
    @State private var dragAnchor: CGFloat?

    private struct GeometryReading: Equatable {
        var offset: CGFloat
        var content: CGFloat
        var container: CGFloat
    }

    private var overflows: Bool { contentWidth > viewportWidth + 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                content()
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: GeometryReading.self, of: { geometry in
                GeometryReading(
                    offset: geometry.contentOffset.x,
                    content: geometry.contentSize.width,
                    container: geometry.containerSize.width
                )
            }) { _, reading in
                offsetX = reading.offset
                contentWidth = reading.content
                viewportWidth = reading.container
            }
            if overflows {
                GeometryReader { proxy in
                    track(trackWidth: max(proxy.size.width, 1))
                }
                .frame(height: 9)
                .padding(.horizontal, trackInset)
            }
        }
    }

    // MARK: The track

    private struct TrackMetrics {
        var thumbWidth: CGFloat
        var thumbX: CGFloat
        var maxThumbX: CGFloat
        var maxOffset: CGFloat
    }

    private func metrics(trackWidth: CGFloat) -> TrackMetrics {
        let fraction = min(viewportWidth / max(contentWidth, 1), 1)
        let thumbWidth = min(max(trackWidth * fraction, 40), trackWidth)
        let maxThumbX = max(trackWidth - thumbWidth, 0)
        let maxOffset = max(contentWidth - viewportWidth, 1)
        let progress = min(max(offsetX / maxOffset, 0), 1)
        return TrackMetrics(
            thumbWidth: thumbWidth,
            thumbX: maxThumbX * progress,
            maxThumbX: maxThumbX,
            maxOffset: maxOffset
        )
    }

    private func track(trackWidth: CGFloat) -> some View {
        let m = metrics(trackWidth: trackWidth)
        let isActive = isHovering || isDragging
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2.5)
                .frame(maxWidth: .infinity)
            Capsule()
                .fill(CanonColor.brass.opacity(isDragging ? 0.95 : (isHovering ? 0.75 : 0.45)))
                .frame(width: m.thumbWidth, height: isActive ? 6.5 : 4.5)
                .offset(x: m.thumbX)
                .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragAnchor == nil {
                        // Grab inside the thumb keeps the grip point; a click
                        // on the bare track jumps the thumb's center there.
                        let inThumb = (m.thumbX...(m.thumbX + m.thumbWidth))
                            .contains(value.startLocation.x)
                        dragAnchor = inThumb
                            ? value.startLocation.x - m.thumbX
                            : m.thumbWidth / 2
                    }
                    isDragging = true
                    guard m.maxThumbX > 0 else { return }
                    let thumbX = min(max(value.location.x - (dragAnchor ?? 0), 0), m.maxThumbX)
                    position.scrollTo(x: thumbX / m.maxThumbX * m.maxOffset)
                }
                .onEnded { _ in
                    isDragging = false
                    dragAnchor = nil
                }
        )
        .help("Scroll — drag the thumb, or click to jump")
    }
}
