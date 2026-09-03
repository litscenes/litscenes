import SwiftUI
import AppKit

/// Identifies which shot's Jovilabe is open.
struct JovilabeRequest: Identifiable, Hashable {
    var shotId: String
    var id: String { shotId }
}

/// The Shot Jovilabe: a per-shot engraved instrument that honestly recounts
/// the shot. Frames sit as 16:9 plates around a graduated dial in sequence
/// order; a fixed pointer marks the current position; the hub magnifies the
/// plate under the pointer; meaning strands render as concentric orbital
/// rings. Drag the dial to scrub (detent snapping), click a plate to seat it,
/// drag a plate to reorder — committed through the same mutation the shot rows
/// use, so the instrument never shows a state that isn't persisted truth or an
/// explicitly lifted, uncommitted plate.
struct ShotJovilabeModal: View {
    let shot: ProjectShot
    let shotOrdinal: Int
    let frameLookup: [String: ProjectLensHeroImage]
    let meaningNodes: [LensContextPromptMeaningNode]
    let workspaceSize: CGSize
    var onMoveEntry: (String, String, Int) -> Void
    var onOpenFrame: (ProjectLensHeroImage) -> Void
    var onClose: () -> Void

    @State private var rotation: Double = 0
    @State private var scrubStartRotation: Double?
    @State private var scrubStartAngle: Double = 0
    @State private var liftedEntryId = ""
    @State private var liftedScreenAngle: Double = 0

    private static let dialSpace = "jovilabeDial"

    private var strands: [MeaningStrand] {
        deriveMeaningStrands(shots: [shot], frameLookup: frameLookup, meaningNodes: meaningNodes)
    }

    private var modalSize: CGSize {
        let width = workspaceSize.width > 0 ? min(max(760, workspaceSize.width * 0.82), 1180) : 980
        let height = workspaceSize.height > 0 ? max(640, workspaceSize.height * 0.92) : 760
        return CGSize(width: width, height: height)
    }

    var body: some View {
        let size = modalSize
        let diameter = min(size.width - 56, size.height - 150)
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            Spacer(minLength: 0)
            instrument(diameter: diameter)
                .frame(width: diameter, height: diameter)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: size.width, height: size.height)
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 0, inset: 6)
        .background(keyboardControls)
        .environment(\.colorScheme, .light)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(PlateColor.hairline).frame(height: 1).frame(maxWidth: 48)
            PlateLabel(text: "Jovilabe · Shot \(FrameCreatorModal.romanNumeral(shotOrdinal))", size: 14, weight: .semibold)
                .fixedSize()
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            if !shot.name.trimmed.isEmpty {
                PlateLabel(text: shot.name, size: 9, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            PlateLabel(
                text: "\(shot.entries.count) plate\(shot.entries.count == 1 ? "" : "s")",
                size: 8.5,
                color: PlateColor.inkFaint
            )
            Spacer()
            Text("Drag the dial to scrub · click a plate to seat it · drag a plate to reorder")
                .font(PlateType.label(9))
                .italic()
                .foregroundStyle(PlateColor.inkFaint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Escape cancels a lift first, then closes; arrows step the detents.
    private var keyboardControls: some View {
        Group {
            Button("") {
                if !liftedEntryId.isEmpty {
                    liftedEntryId = ""
                } else {
                    onClose()
                }
            }
            .keyboardShortcut(.cancelAction)
            Button("") { step(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { step(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func step(by delta: Int) {
        let count = shot.entries.count
        guard count > 0 else { return }
        let current = JovilabeGeometry.pointerIndex(rotationDegrees: rotation, count: count)
        let next = ((current + delta) % count + count) % count
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            rotation = JovilabeGeometry.rotation(bringing: next, count: count, from: rotation)
        }
    }

    // MARK: Instrument

    private func instrument(diameter: CGFloat) -> some View {
        let count = shot.entries.count
        let plateWidth = max(120, diameter * 0.17)
        let plateHeight = plateWidth * 9 / 16
        let ringRadius = diameter / 2 - plateHeight / 2 - 26
        let hubDiameter = diameter * 0.42
        return ZStack {
            dialChrome(diameter: diameter)
                .contentShape(Circle())
                .gesture(scrubGesture(diameter: diameter))
            rotatingLayer(
                count: count,
                plateWidth: plateWidth,
                plateHeight: plateHeight,
                ringRadius: ringRadius,
                hubRadius: hubDiameter / 2,
                diameter: diameter
            )
            if let lifted = liftedEntry, count > 0 {
                liftedPlate(lifted, width: plateWidth, height: plateHeight, ringRadius: ringRadius)
            }
            hub(diameter: hubDiameter)
            PlatePointer()
                .fill(PlateColor.ink)
                .frame(width: 26, height: 16)
                .rotationEffect(.degrees(90)) // point downward at the ring's top station
                .offset(y: -(ringRadius + plateHeight / 2 + 14))
        }
        .coordinateSpace(name: Self.dialSpace)
    }

    private func dialChrome(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(PlateColor.ink, lineWidth: 1)
                .frame(width: diameter, height: diameter)
            PlateTickRing(tickCount: 240, majorEvery: 10, minorLength: 4, majorLength: 9)
                .stroke(PlateColor.ink.opacity(0.7), lineWidth: 0.6)
                .frame(width: diameter - 6, height: diameter - 6)
            Circle()
                .stroke(PlateColor.hairline, lineWidth: 0.75)
                .frame(width: diameter - 24, height: diameter - 24)
        }
    }

    // MARK: Rotating layer (plates + strand orbits)

    private var liftedEntry: ShotFrameEntry? {
        shot.entries.first { $0.entryId == liftedEntryId }
    }

    /// The plates and strand rings rotate together; every element's angle is a
    /// pure function of the persisted order (or the explicit lift preview).
    private func rotatingLayer(
        count: Int,
        plateWidth: CGFloat,
        plateHeight: CGFloat,
        ringRadius: CGFloat,
        hubRadius: CGFloat,
        diameter: CGFloat
    ) -> some View {
        let placements = platePlacements(count: count)
        return ZStack {
            strandOrbits(hubRadius: hubRadius, ringRadius: ringRadius - plateHeight / 2 - 10, diameter: diameter)
            ForEach(placements, id: \.entry.entryId) { placement in
                plateView(placement.entry, ordinal: placement.ordinal, width: plateWidth, height: plateHeight)
                    .rotationEffect(.degrees(-(placement.angle + rotation)))
                    .offset(y: -ringRadius)
                    .rotationEffect(.degrees(placement.angle))
            }
        }
        .rotationEffect(.degrees(rotation))
    }

    private struct PlatePlacement {
        var entry: ShotFrameEntry
        var ordinal: Int   // 1-based position the plate occupies (preview-aware)
        var angle: Double
    }

    /// Persisted order normally; during a lift, the remaining plates re-seat
    /// into the exact arrangement release would commit (gap at the insertion
    /// index), so the preview IS the promise.
    private func platePlacements(count: Int) -> [PlatePlacement] {
        guard count > 0 else { return [] }
        if liftedEntryId.isEmpty || liftedEntry == nil {
            return shot.entries.enumerated().map { index, entry in
                PlatePlacement(entry: entry, ordinal: index + 1, angle: JovilabeGeometry.plateAngle(index: index, count: count))
            }
        }
        let insertion = JovilabeGeometry.insertionIndex(
            atScreenAngle: liftedScreenAngle,
            rotationDegrees: rotation,
            count: count
        )
        let remaining = shot.entries.filter { $0.entryId != liftedEntryId }
        var placements: [PlatePlacement] = []
        var cursor = 0
        for slot in 0..<count {
            if slot == insertion { continue } // the open gap tracking the lifted plate
            guard cursor < remaining.count else { break }
            placements.append(PlatePlacement(
                entry: remaining[cursor],
                ordinal: slot + 1,
                angle: JovilabeGeometry.plateAngle(index: slot, count: count)
            ))
            cursor += 1
        }
        return placements
    }

    private func plateView(_ entry: ShotFrameEntry, ordinal: Int, width: CGFloat, height: CGFloat) -> some View {
        let frame = frameLookup[entry.frameImageId]
        return ZStack(alignment: .topLeading) {
            plateThumbnail(frame: frame)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(FrameCreatorModal.romanNumeral(ordinal))
                .font(PlateType.figure(9, weight: .semibold))
                .foregroundStyle(PlateColor.cream)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 2).fill(PlateColor.ink.opacity(0.85)))
                .padding(4)
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PlateColor.ink, lineWidth: 0.9))
        .opacity(entry.entryId == liftedEntryId ? 0 : 1)
        .onTapGesture {
            seat(entry)
        }
        .gesture(liftGesture(entry))
        .help(frame?.label.trimmed.nilIfEmpty ?? "Plate \(FrameCreatorModal.romanNumeral(ordinal))")
    }

    @ViewBuilder
    private func plateThumbnail(frame: ProjectLensHeroImage?) -> some View {
        ZStack {
            PlateColor.creamDeep
            if let frame, frame.status == "ready", !frame.imagePath.trimmed.isEmpty,
               let image = NSImage(contentsOfFile: frame.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: frame == nil ? "questionmark.square.dashed" : (frame?.status == "generating" ? "hourglass" : "exclamationmark.triangle"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                    Text(frame == nil ? "MISSING" : (frame?.status ?? "").uppercased())
                        .font(PlateType.label(6.5, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                }
            }
        }
        .clipped()
    }

    private func seat(_ entry: ShotFrameEntry) {
        guard let index = shot.entries.firstIndex(where: { $0.entryId == entry.entryId }) else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            rotation = JovilabeGeometry.rotation(bringing: index, count: shot.entries.count, from: rotation)
        }
    }

    // MARK: Strand orbits

    private func strandOrbits(hubRadius: CGFloat, ringRadius: CGFloat, diameter: CGFloat) -> some View {
        let strands = strands
        let count = shot.entries.count
        let innerMost = hubRadius + 22
        let available = max(0, ringRadius - innerMost)
        let spacing = strands.count > 1 ? min(16, available / CGFloat(max(1, strands.count - 1))) : 0
        let currentRotation = rotation
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (strandIndex, strand) in strands.enumerated() {
                guard count > 0 else { continue }
                let radius = min(ringRadius, innerMost + CGFloat(strandIndex) * spacing)
                let hue = MeaningStrandPalette.hue(at: strand.hueIndex)

                // The orbit: a full hairline circle.
                let orbit = Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                ))
                context.stroke(orbit, with: .color(PlateColor.hairlineFaint), lineWidth: 0.75)

                // Touched angles in sequence order (dial space; the whole canvas rotates).
                let angles = strand.touches.map {
                    JovilabeGeometry.plateAngle(index: $0.entryIndex, count: count)
                }
                func point(_ degrees: Double) -> CGPoint {
                    let radians = (degrees - 90) * .pi / 180 // 0° = top
                    return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
                }

                // Hue arcs along the orbit between consecutive touches.
                for pair in zip(angles, angles.dropFirst()) {
                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(pair.0 - 90),
                        endAngle: .degrees(pair.1 - 90),
                        clockwise: false
                    )
                    context.stroke(arc, with: .color(hue.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                // Node dots at each touched plate's angle.
                for degrees in angles {
                    let p = point(degrees)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(PlateColor.cream))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(hue))
                }

                // Label at the first touch, counter-rotated so it reads upright.
                if let firstAngle = angles.first {
                    let p = point(firstAngle)
                    var labelContext = context
                    labelContext.translateBy(x: p.x, y: p.y + 10)
                    labelContext.rotate(by: .degrees(-currentRotation))
                    let text = labelContext.resolve(
                        Text(strand.label.uppercased())
                            .font(PlateType.label(6.5, weight: .semibold))
                            .foregroundStyle(hue)
                    )
                    labelContext.draw(text, at: .zero, anchor: .center)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    // MARK: Hub magnifier

    private var pointerEntry: ShotFrameEntry? {
        let count = shot.entries.count
        guard count > 0 else { return nil }
        let index = JovilabeGeometry.pointerIndex(rotationDegrees: rotation, count: count)
        return shot.entries.indices.contains(index) ? shot.entries[index] : nil
    }

    private func hub(diameter: CGFloat) -> some View {
        let entry = pointerEntry
        let frame = entry.flatMap { frameLookup[$0.frameImageId] }
        let count = shot.entries.count
        let index = count > 0 ? JovilabeGeometry.pointerIndex(rotationDegrees: rotation, count: count) : 0
        let imageWidth = diameter * 0.78
        return ZStack {
            Circle().fill(PlateColor.cream)
            Circle().stroke(PlateColor.ink, lineWidth: 1)
            if count == 0 {
                PlateLabel(text: "No plates", size: 9, color: PlateColor.inkFaint)
            } else {
                VStack(spacing: 7) {
                    PlateLabel(text: "Plate \(FrameCreatorModal.romanNumeral(index + 1)) of \(FrameCreatorModal.romanNumeral(count))", size: 8.5, color: PlateColor.inkFaint)
                    plateThumbnail(frame: frame)
                        .frame(width: imageWidth, height: imageWidth * 9 / 16)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PlateColor.ink, lineWidth: 0.9))
                        .onTapGesture {
                            if let frame, frame.status == "ready" {
                                onOpenFrame(frame)
                            }
                        }
                        .help(frame?.status == "ready" ? "Open this frame" : "")
                    if let frame, !frame.label.trimmed.isEmpty {
                        Text(frame.label)
                            .font(PlateType.label(9.5, weight: .semibold))
                            .foregroundStyle(PlateColor.ink)
                            .lineLimit(1)
                            .frame(maxWidth: imageWidth)
                    }
                    if let entry {
                        hubStrandChips(entryId: entry.entryId)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func hubStrandChips(entryId: String) -> some View {
        let memberships = strands.filter { strand in
            strand.touches.contains { $0.entryId == entryId }
        }
        return HStack(spacing: 8) {
            ForEach(memberships) { strand in
                HStack(spacing: 3) {
                    Circle()
                        .fill(MeaningStrandPalette.hue(at: strand.hueIndex))
                        .frame(width: 5, height: 5)
                    Text(strand.label.uppercased())
                        .font(PlateType.label(6.5, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                        .lineLimit(1)
                }
                .help(strand.detail)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Gestures

    /// Angle (degrees, 0° = top, clockwise) of a point in dial space.
    private func screenAngle(of point: CGPoint, diameter: CGFloat) -> Double {
        let center = Double(diameter / 2)
        let dx = Double(point.x) - center
        let dy = Double(point.y) - center
        let radians = atan2(dx, -dy)
        return JovilabeGeometry.normalizedDegrees(radians * 180 / Double.pi)
    }

    private func scrubGesture(diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.dialSpace))
            .onChanged { value in
                let angle = screenAngle(of: value.location, diameter: diameter)
                if scrubStartRotation == nil {
                    scrubStartRotation = rotation
                    scrubStartAngle = screenAngle(of: value.startLocation, diameter: diameter)
                }
                var delta = angle - scrubStartAngle
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                rotation = (scrubStartRotation ?? rotation) + delta
            }
            .onEnded { _ in
                scrubStartRotation = nil
                let count = shot.entries.count
                guard count > 0 else { return }
                let nearest = JovilabeGeometry.pointerIndex(rotationDegrees: rotation, count: count)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    rotation = JovilabeGeometry.rotation(bringing: nearest, count: count, from: rotation)
                }
            }
    }

    private func liftGesture(_ entry: ShotFrameEntry) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.dialSpace))
            .onChanged { value in
                liftedEntryId = entry.entryId
                liftedScreenAngle = screenAngle(of: value.location, diameter: modalDialDiameter)
            }
            .onEnded { value in
                defer { liftedEntryId = "" }
                let count = shot.entries.count
                guard count > 0,
                      let sourceIndex = shot.entries.firstIndex(where: { $0.entryId == entry.entryId }) else {
                    return
                }
                let finalIndex = JovilabeGeometry.insertionIndex(
                    atScreenAngle: screenAngle(of: value.location, diameter: modalDialDiameter),
                    rotationDegrees: rotation,
                    count: count
                )
                guard finalIndex != sourceIndex else { return }
                onMoveEntry(
                    shot.shotId,
                    entry.entryId,
                    JovilabeGeometry.moveGapIndex(finalIndex: finalIndex, sourceIndex: sourceIndex)
                )
            }
    }

    private var modalDialDiameter: CGFloat {
        let size = modalSize
        return min(size.width - 56, size.height - 150)
    }

    private func liftedPlate(_ entry: ShotFrameEntry, width: CGFloat, height: CGFloat, ringRadius: CGFloat) -> some View {
        let radians = (liftedScreenAngle - 90) * .pi / 180
        let position = CGPoint(x: ringRadius * cos(radians), y: ringRadius * sin(radians))
        return plateThumbnail(frame: frameLookup[entry.frameImageId])
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(PlateColor.ink, lineWidth: 1.2))
            .scaleEffect(1.07)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
            .offset(x: position.x, y: position.y)
            .allowsHitTesting(false)
    }
}
