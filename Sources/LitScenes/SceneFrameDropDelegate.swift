import SwiftUI
import UniformTypeIdentifiers

struct SceneFrameDropBoundaryKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// One row-wide destination: video presentation cards never become placements.
struct SceneFrameDropDelegate: DropDelegate {
    var boundaries: [Int: CGFloat]
    var allowedBoundaries: Set<Int>
    var viewportOffset: CGFloat
    var viewportWidth: CGFloat
    @Binding var active: Bool
    @Binding var target: Int?
    @Binding var scrollDirection: Int
    @Binding var error: String
    var onDrop: (ShotFrameTransfer, Int) -> String?

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.json]) }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: target == nil ? .forbidden : .copy)
    }
    func dropExited(info: DropInfo) { clear() }
    private func update(_ info: DropInfo) {
        active = true
        target = nearest(info.location.x)
        let lockMessage = "Rendered frames are locked. Use New Version to rearrange them."
        if target == nil { error = lockMessage }
        else if error == lockMessage { error = "" }
        let x = info.location.x - viewportOffset
        scrollDirection = x < 40 ? -1 : (x > viewportWidth - 40 ? 1 : 0)
    }
    private func nearest(_ x: CGFloat) -> Int? {
        guard let index = boundaries.min(by: { abs($0.value - x) < abs($1.value - x) })?.key,
              allowedBoundaries.contains(index) else { return nil }
        return index
    }
    private func clear() { active = false; target = nil; scrollDirection = 0 }
    func performDrop(info: DropInfo) -> Bool {
        guard let index = nearest(info.location.x), let provider = info.itemProviders(for: [.json]).first else {
            error = "This sequence is locked. Use New Version to rearrange its rendered frames."
            clear()
            return false
        }
        clear()
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            let transfer = data.flatMap { try? JSONDecoder().decode(ShotFrameTransfer.self, from: $0) }
            Task { @MainActor in
                guard let transfer else { error = "Could not read the dragged frame — retry"; return }
                error = onDrop(transfer, index) ?? ""
            }
        }
        return true
    }
}
