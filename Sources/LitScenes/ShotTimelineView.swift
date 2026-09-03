import SwiftUI
import AppKit

// The SHOTS band (ShotTimelineBoard) that lived here was retired by the
// STAGE / CUT canvas: stages gather inputs on plates in the page scroll and
// each cut strip (CutStripView) carries the row anatomy forward — no more
// height-capped nested scroll pinned above the frames. Strand derivation
// stays in ShotTimelineModels (narration still reads it); only the braided
// canvas UI went away with the band.

/// Context-menu items that gather a video or trim onto a STAGE without a
/// drag — the click path for footage rows anywhere they appear (the
/// Moodboard's Video Sources tray, the Scenes sidebar's Footage tab). Stage
/// ops are engine-global, so this works from any screen; placing the clip
/// into a specific cut happens on the stage plate afterward (or by dropping
/// the row straight onto a cut strip).
struct FootageStageMenu: View {
    @ObservedObject var library: LibraryEngine
    let mediaId: String

    var body: some View {
        ForEach(library.stageSet.stages) { stage in
            Button {
                library.addStageClipInput(stageId: stage.stageId, mediaId: mediaId)
            } label: {
                Label(stageMenuTitle(stage), systemImage: "square.stack.3d.up")
            }
        }
        Button {
            let stageId = library.createStage()
            library.addStageClipInput(stageId: stageId, mediaId: mediaId)
        } label: {
            Label("New stage from this footage", systemImage: "plus.rectangle.on.rectangle")
        }
    }

    private func stageMenuTitle(_ stage: ProjectStage) -> String {
        let name = stage.name.trimmed
        return name.isEmpty
            ? "Gather on unnamed stage (\(stage.inputs.count) gathered)"
            : "Gather on \(name)"
    }
}
