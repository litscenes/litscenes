import AppKit
import SwiftUI

/// EXCURSION MODE: the full-screen punch-in dive surface. The current frame
/// fills the screen; a click on a detail IMMEDIATELY performs a geometric
/// camera push into the clicked crop (real parent pixels, no AI wait) while
/// the same click mints a real zoom-in reframe child and inserts the
/// there-and-back excursion into the cut. Async results upgrade in place —
/// the child still crossfades over the magnified crop when it lands, and a
/// rendered pull-out segment clip replaces the reverse morph when one exists.
/// Esc / a letterbox click pulls back one level; at the root it exits.
/// Exploration IS authoring: leaving the mode keeps every excursion.
struct ExcursionModeView: View {
    @ObservedObject var library: LibraryEngine
    let request: ExcursionLaunchRequest
    /// The one engine call per dive, owned by the workbench so it can resolve
    /// the lens, compose the default reframe prompt, and register Undo:
    /// (afterEntryId, parentImageId, spec, onPlaced) → started.
    let startPunchIn: (
        _ afterEntryId: String,
        _ parentImageId: String,
        _ spec: LensReframeSpec,
        _ onPlaced: @escaping @MainActor (ShotPunchInPlacement) -> Void
    ) async -> Bool
    let onExit: () -> Void

    private enum SurfacePhase: Equatable {
        case settled
        case pushingIn(nodeId: String)
        case pullingOut(nodeId: String)
        case playingSegment(nodeId: String)
    }

    @State private var diveStack: [ExcursionDiveNode] = []
    @State private var phase: SurfacePhase = .settled
    /// The normalized visible rect over the current BASE still — the camera.
    @State private var cameraRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The top dive's child-still overlay opacity (the honest crossfade).
    @State private var childOpacity: Double = 0
    @State private var hoverPoint: CGPoint?
    /// Refusals render HERE — the workbench's status chrome is covered.
    @State private var actionStatus = ""
    @State private var imageCache: [String: NSImage] = [:]
    @State private var segmentClipPath = ""
    @State private var segmentTimestamp: Double = 0

    private static let pushDuration: Double = 0.85
    private static let crossfadeDuration: Double = 0.4

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                canvas(containerSize: proxy.size)
                hud
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                handleTap(at: value.location, containerSize: proxy.size)
            })
            .onContinuousHover { hoverPhase in
                switch hoverPhase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The house Esc pattern: a hidden cancel-action button needs no
            // focus plumbing and always receives the press.
            Button("") { pullBack() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .onExitCommand { pullBack() }
        .onChange(of: topMaterial) { _, material in
            // The honest upgrade: the child still crossfades in the moment
            // the engine flips it ready and the file is on disk.
            if case .childStill = material, phase == .settled, childOpacity == 0 {
                withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
                    childOpacity = 1
                }
            }
        }
    }

    // MARK: Derived state

    private var cut: ProjectShot? {
        library.shotTimeline.shots.first { $0.shotId == request.cutId }
    }

    private var frameLookup: [String: ProjectLensHeroImage] {
        library.projectWideFrameLookup
    }

    private var topNode: ExcursionDiveNode? { diveStack.last }

    private var topMaterial: ExcursionNodeMaterial {
        guard let node = topNode else { return .parentCrop }
        return excursionNodeMaterial(childImageId: node.childImageId, frameLookup: frameLookup)
    }

    /// The base still the camera transforms: the top dive's PARENT (its crop
    /// is what the geometric morph magnifies), or the root frame at depth 0.
    private var baseImagePath: String? {
        let imageId = topNode?.parentImageId ?? request.rootImageId
        guard let frame = frameLookup[imageId], frame.status == "ready",
              !frame.imagePath.trimmed.isEmpty else { return nil }
        return frame.imagePath
    }

    /// The ready still currently on screen — the only diveable material.
    private var displayedStill: (imageId: String, path: String)? {
        guard let node = topNode else {
            guard let path = baseImagePath else { return nil }
            return (request.rootImageId, path)
        }
        if case .childStill(let path) = topMaterial, childOpacity == 1 {
            return (node.childImageId, path)
        }
        return nil
    }

    /// A dive departs from the displayed still's cut placement.
    private var displayedEntryId: String {
        topNode?.childEntryId ?? request.entryId
    }

    private func cachedImage(path: String) -> NSImage? {
        if let cached = imageCache[path] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        // State mutation during view update is illegal; defer the cache fill.
        DispatchQueue.main.async { imageCache[path] = image }
        return image
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvas(containerSize: CGSize) -> some View {
        if let basePath = baseImagePath, let baseImage = cachedImage(path: basePath) {
            let fitted = excursionFittedFrame(
                imagePixelSize: baseImage.size, containerSize: containerSize
            )
            ZStack {
                // The camera layer: the REAL base still under the animated
                // visible-rect transform, wearing its rendered reframe
                // children as inlaid puzzle pieces — the pieces ride every
                // morph because they live in the same transformed space.
                // During a hold this is the magnified parent crop — honest
                // material, never a faked frame.
                ZStack {
                    Image(nsImage: baseImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitted.width, height: fitted.height)
                    puzzleLayer(
                        parentImageId: topNode?.parentImageId ?? request.rootImageId,
                        fitted: fitted,
                        isDisplayedLayer: displayedStill?.imageId == (topNode?.parentImageId ?? request.rootImageId)
                    )
                }
                .frame(width: fitted.width, height: fitted.height)
                .modifier(ExcursionCameraModifier(
                    midX: cameraRect.midX,
                    midY: cameraRect.midY,
                    width: cameraRect.width,
                    height: cameraRect.height,
                    fittedSize: fitted.size
                ))
                .frame(width: fitted.width, height: fitted.height)
                .clipped()

                // The child still, full-frame over its own crop region —
                // wearing ITS children as pieces once it is the displayed
                // material, so the puzzle recurses with the dive.
                if let node = topNode, case .childStill(let childPath) = topMaterial,
                   let childImage = cachedImage(path: childPath) {
                    ZStack {
                        Image(nsImage: childImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fitted.width, height: fitted.height)
                        if phase == .settled, childOpacity == 1 {
                            puzzleLayer(
                                parentImageId: node.childImageId,
                                fitted: fitted,
                                isDisplayedLayer: true
                            )
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .opacity(childOpacity)
                    .id(node.nodeId)
                }

                // A rendered segment clip replaces the geometric morph.
                if case .playingSegment = phase, !segmentClipPath.isEmpty {
                    ScrubVideoPreview(
                        path: segmentClipPath,
                        timestampSeconds: $segmentTimestamp,
                        isFreePlaying: true,
                        onPlaybackEnded: { finishSegmentPlayback() }
                    )
                    .frame(width: fitted.width, height: fitted.height)
                }

                if let reticle = hoverReticleRect(fitted: fitted, baseImage: baseImage) {
                    ExcursionHoverReticle(rect: reticle)
                }
            }
            .position(x: containerSize.width / 2, y: containerSize.height / 2)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CanonColor.muted.opacity(0.75))
                Text("FRAME UNAVAILABLE")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted)
            }
        }
    }

    /// The rendered reframe children of `parentImageId`, inlaid at their
    /// exact crop regions. On the displayed layer a hovered piece highlights
    /// (a click revisits it for $0 instead of minting a new dive).
    @ViewBuilder
    private func puzzleLayer(
        parentImageId: String,
        fitted: CGRect,
        isDisplayedLayer: Bool
    ) -> some View {
        let pieces = excursionPuzzlePieces(parentImageId: parentImageId, frameLookup: frameLookup)
        let hovered = isDisplayedLayer ? hoveredPiece(fitted: fitted, pieces: pieces) : nil
        ForEach(pieces) { piece in
            if let image = cachedImage(path: piece.imagePath) {
                let isHovered = hovered?.imageId == piece.imageId
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: piece.rect.width * fitted.width,
                        height: piece.rect.height * fitted.height
                    )
                    .clipped()
                    .overlay(
                        Rectangle().strokeBorder(
                            isHovered ? CanonColor.brass : CanonColor.bone.opacity(0.45),
                            lineWidth: isHovered ? 1.5 : 1
                        )
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.55 : 0.35), radius: isHovered ? 7 : 4)
                    .rotationEffect(.degrees(piece.rotationDegrees))
                    .position(
                        x: piece.rect.midX * fitted.width,
                        y: piece.rect.midY * fitted.height
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    /// The piece under the cursor on the displayed material, if any.
    private func hoveredPiece(
        fitted: CGRect,
        pieces: [ExcursionPuzzlePiece]
    ) -> ExcursionPuzzlePiece? {
        guard phase == .settled, let hoverPoint,
              let normalized = excursionNormalizedPoint(
                  viewPoint: hoverPoint, fittedFrame: fitted
              ) else { return nil }
        return excursionPuzzlePieceHit(point: normalized, pieces: pieces)
    }

    /// The hover outline of exactly the 16:9 region a click commits — armed
    /// only while the displayed material is a ready, diveable still, and
    /// suppressed over a puzzle piece (there the click revisits instead).
    private func hoverReticleRect(fitted: CGRect, baseImage: NSImage) -> CGRect? {
        guard phase == .settled, let still = displayedStill, let hoverPoint else { return nil }
        guard let normalized = excursionNormalizedPoint(
            viewPoint: hoverPoint, fittedFrame: fitted
        ) else { return nil }
        guard excursionPuzzlePieceHit(
            point: normalized,
            pieces: excursionPuzzlePieces(parentImageId: still.imageId, frameLookup: frameLookup)
        ) == nil else { return nil }
        let focus = lensReframeFocusRect(
            center: normalized,
            imagePixelSize: baseImage.size
        )
        guard !focus.isEmpty else { return nil }
        // Focus rect is normalized over the image; the canvas ZStack is
        // centered on the fitted frame, so convert to its local coordinates.
        return CGRect(
            x: focus.minX * fitted.width,
            y: focus.minY * fitted.height,
            width: focus.width * fitted.width,
            height: focus.height * fitted.height
        )
    }

    // MARK: HUD

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                Text(breadcrumb)
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.bone)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                Spacer()
                Button {
                    onExit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Leave Excursion mode — every dive stays in the cut")
            }
            Spacer()
            HStack(alignment: .bottom) {
                statusBadge
                Spacer()
                if !actionStatus.isEmpty {
                    Text(actionStatus)
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(CanonColor.bone)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
            }
        }
        .padding(18)
    }

    private var breadcrumb: String {
        let cutName = cut.map { $0.name.trimmed.isEmpty ? "CUT" : $0.name.uppercased() } ?? "CUT"
        guard !diveStack.isEmpty else { return cutName }
        let dives = (1...diveStack.count).map { "DIVE \($0)" }.joined(separator: " › ")
        return "\(cutName) › \(dives)"
    }

    @ViewBuilder
    private var statusBadge: some View {
        if topNode != nil {
            switch topMaterial {
            case .parentCrop where phase == .settled:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(topNode?.childImageId.isEmpty == false
                         && frameLookup[topNode?.childImageId ?? ""]?.status == "queued"
                        ? "QUEUED" : "RENDERING REFRAME")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.bone)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
            case .failed(let message):
                Text("REFRAME FAILED — \(message)")
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.45, green: 0.12, blue: 0.1).opacity(0.85)))
            default:
                EmptyView()
            }
        }
    }

    // MARK: Interaction

    private func handleTap(at viewPoint: CGPoint, containerSize: CGSize) {
        guard phase == .settled else { return }
        guard let still = displayedStill, let baseImage = stillImageForTap(still) else {
            // Nothing diveable on screen (hold, failure, missing frame): a
            // click steps back instead of minting from unseen pixels.
            pullBack()
            return
        }
        let fitted = excursionFittedFrame(
            imagePixelSize: baseImage.size, containerSize: containerSize
        )
        guard let normalized = excursionNormalizedPoint(
            viewPoint: viewPoint, fittedFrame: fitted
        ) else {
            pullBack()
            return
        }
        // A click on an inlaid puzzle piece REVISITS that existing rendered
        // reframe — no new render, no insertion — instead of minting a dive.
        if let piece = excursionPuzzlePieceHit(
            point: normalized,
            pieces: excursionPuzzlePieces(parentImageId: still.imageId, frameLookup: frameLookup)
        ) {
            revisitDive(piece: piece, parentImageId: still.imageId)
            return
        }
        guard !displayedEntryId.isEmpty else {
            actionStatus = topNode?.isRevisit == true
                ? "This reframe isn't placed in the cut — new dives need a placement to land beside"
                : "This dive is still landing in the cut — one moment"
            return
        }
        guard let spec = excursionDiveSpec(
            clickPoint: normalized,
            imagePixelSize: baseImage.size,
            parentImageId: still.imageId
        ) else { return }
        commitDive(spec: spec, parentEntryId: displayedEntryId)
    }

    /// The puzzle-piece dive: fly into the piece's footprint and settle on
    /// the ALREADY-RENDERED child — free, view-only, and anchored to the
    /// child's existing cut placement when one exists (which re-arms deeper
    /// dives and the rendered pull-out clip).
    private func revisitDive(piece: ExcursionPuzzlePiece, parentImageId: String) {
        actionStatus = ""
        guard let child = frameLookup[piece.imageId], let spec = child.reframe else { return }
        let placement = excursionExistingPlacement(
            cut: cut, childImageId: piece.imageId, parentImageId: parentImageId
        )
        var node = ExcursionDiveNode(
            nodeId: UUID().uuidString,
            spec: spec,
            parentImageId: parentImageId,
            parentEntryId: displayedEntryId,
            childImageId: piece.imageId,
            childEntryId: placement?.childEntryId ?? "",
            returnEntryId: placement?.returnEntryId ?? ""
        )
        node.isRevisit = true
        diveStack.append(node)
        childOpacity = 0
        cameraRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        phase = .pushingIn(nodeId: node.nodeId)
        withAnimation(.easeInOut(duration: Self.pushDuration)) {
            cameraRect = piece.rect
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64((Self.pushDuration + 0.05) * 1_000_000_000))
            if phase == .pushingIn(nodeId: node.nodeId) {
                phase = .settled
                // The magnified piece already shows the child's pixels; the
                // full-frame child fades in for full resolution (and to
                // straighten a tilted piece).
                withAnimation(.easeInOut(duration: 0.2)) {
                    childOpacity = 1
                }
            }
        }
    }

    private func stillImageForTap(_ still: (imageId: String, path: String)) -> NSImage? {
        cachedImage(path: still.path)
    }

    private func commitDive(spec: LensReframeSpec, parentEntryId: String) {
        actionStatus = ""
        let node = ExcursionDiveNode(
            nodeId: UUID().uuidString,
            spec: spec,
            parentImageId: spec.parentImageId,
            parentEntryId: parentEntryId
        )
        // Re-root the camera on the newly displayed still (visually identical
        // to the frame on screen), then fly into the clicked crop.
        diveStack.append(node)
        childOpacity = 0
        cameraRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        phase = .pushingIn(nodeId: node.nodeId)
        withAnimation(.easeInOut(duration: Self.pushDuration)) {
            cameraRect = CGRect(
                x: spec.centerX - spec.normalizedWidth / 2,
                y: spec.centerY - spec.normalizedHeight / 2,
                width: spec.normalizedWidth,
                height: spec.normalizedHeight
            )
        }
        Task {
            let started = await startPunchIn(parentEntryId, spec.parentImageId, spec) { placement in
                guard let index = diveStack.firstIndex(where: { $0.nodeId == node.nodeId }) else { return }
                diveStack[index].childImageId = placement.childImageId
                diveStack[index].childEntryId = placement.childEntryId
                diveStack[index].returnEntryId = placement.returnEntryId
            }
            if !started {
                failDive(nodeId: node.nodeId)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64((Self.pushDuration + 0.05) * 1_000_000_000))
            if phase == .pushingIn(nodeId: node.nodeId) {
                phase = .settled
            }
        }
    }

    /// The engine refused (frozen cut, unsupported stack, spend gate…):
    /// reverse the morph, drop the node, and state the refusal in-surface.
    private func failDive(nodeId: String) {
        guard let index = diveStack.firstIndex(where: { $0.nodeId == nodeId }) else { return }
        diveStack.remove(at: index)
        let refusal = library.aestheticStatus.trimmed
        actionStatus = refusal.isEmpty ? "The dive could not start" : refusal
        phase = .settled
        withAnimation(.easeInOut(duration: 0.45)) {
            settleCameraForTop()
        }
    }

    private func pullBack() {
        guard phase == .settled else { return }
        guard let node = topNode else {
            onExit()
            return
        }
        actionStatus = ""
        let media = excursionTransitionMedia(
            cut: cut,
            startEntryId: node.childEntryId,
            endEntryId: node.returnEntryId,
            startImageId: node.childImageId,
            endImageId: node.parentImageId
        )
        switch media {
        case .segmentVideo(let path):
            segmentClipPath = path
            segmentTimestamp = 0
            phase = .playingSegment(nodeId: node.nodeId)
        case .geometric:
            phase = .pullingOut(nodeId: node.nodeId)
            withAnimation(.easeInOut(duration: 0.25)) {
                childOpacity = 0
            }
            withAnimation(.easeInOut(duration: Self.pushDuration)) {
                cameraRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64((Self.pushDuration + 0.05) * 1_000_000_000))
                if phase == .pullingOut(nodeId: node.nodeId) {
                    finishPullOut()
                }
            }
        }
    }

    private func finishSegmentPlayback() {
        segmentClipPath = ""
        finishPullOut()
    }

    private func finishPullOut() {
        guard !diveStack.isEmpty else { return }
        diveStack.removeLast()
        settleCameraForTop()
        phase = .settled
    }

    /// The settled camera for the current top: a ready child shows full-frame
    /// (overlay at 1 over its own magnified crop); a held dive stays on the
    /// magnified parent crop; the root shows the whole frame.
    private func settleCameraForTop() {
        guard let node = topNode else {
            cameraRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            childOpacity = 0
            return
        }
        cameraRect = CGRect(
            x: node.spec.centerX - node.spec.normalizedWidth / 2,
            y: node.spec.centerY - node.spec.normalizedHeight / 2,
            width: node.spec.normalizedWidth,
            height: node.spec.normalizedHeight
        )
        if case .childStill = excursionNodeMaterial(
            childImageId: node.childImageId, frameLookup: frameLookup
        ) {
            childOpacity = 1
        } else {
            childOpacity = 0
        }
    }
}

/// A true camera path: the animatable data is the visible rect itself, so the
/// scale and the pan interpolate together instead of drifting independently.
private struct ExcursionCameraModifier: ViewModifier, Animatable {
    var midX: CGFloat
    var midY: CGFloat
    var width: CGFloat
    var height: CGFloat
    var fittedSize: CGSize

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(midX, midY), AnimatablePair(width, height)) }
        set {
            midX = newValue.first.first
            midY = newValue.first.second
            width = newValue.second.first
            height = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        let transform = excursionCameraTransform(
            visibleRect: CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height),
            fittedImageSize: fittedSize
        )
        content
            .scaleEffect(transform.scale)
            .offset(transform.offset)
    }
}

/// The 16:9 outline of exactly the region a click commits.
private struct ExcursionHoverReticle: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .strokeBorder(CanonColor.brass.opacity(0.9), lineWidth: 1.5)
            .background(Rectangle().fill(CanonColor.brass.opacity(0.06)))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}
