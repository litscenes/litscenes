import Foundation

/// Optional on a reframe spec so saved compass-based viewpoints keep their meaning.
struct LensCameraTurn: Codable, Hashable, Sendable {
    static let templateMode = "camera_turn"
    var yawDegrees: Double = 0
    var pitchDegrees: Double = 0
    var operatorNotes: String = ""

    func normalized() -> Self {
        var value = self
        value.yawDegrees = Self.angle(yawDegrees, limit: 180)
        value.pitchDegrees = Self.angle(pitchDegrees, limit: 90)
        return value
    }

    private static func angle(_ value: Double, limit: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(limit, max(-limit, (value / 5).rounded() * 5))
    }

    var summary: String {
        let turn = normalized()
        let yaw = turn.yawDegrees == 0 ? "Forward" : "\(Int(abs(turn.yawDegrees)))° \(turn.yawDegrees > 0 ? "right" : "left")"
        let pitch = turn.pitchDegrees == 0 ? "level" : "\(Int(abs(turn.pitchDegrees)))° \(turn.pitchDegrees > 0 ? "up" : "down")"
        return "\(yaw) · \(pitch)"
    }

    static func referenceSummary(spec: LensReframeSpec) -> String {
        guard let turn = spec.cameraTurn?.normalized() else { return "" }
        return "position \(LensReframeComposer.percent(spec.centerX))% across, \(LensReframeComposer.percent(spec.centerY))% down; fixed position; yaw \(Int(turn.yawDegrees))°, pitch \(Int(turn.pitchDegrees))° (positive = right / up); level roll."
    }

    static func instructions(spec: LensReframeSpec) -> String {
        guard let turn = spec.cameraTurn?.normalized() else { return "" }
        return """
        Create one still image from a camera placed at the selected scene location, \(LensReframeComposer.percent(spec.centerX))% from the source image's left edge and \(LensReframeComposer.percent(spec.centerY))% from its top. This point identifies the camera position, not a subject to orbit.
        From that fixed position, begin facing parallel to the original camera's forward direction, then turn \(Int(abs(turn.yawDegrees))) degrees \(turn.yawDegrees < 0 ? "left" : "right") and tilt \(Int(abs(turn.pitchDegrees))) degrees \(turn.pitchDegrees < 0 ? "down" : "up"). Zero turn means forward; zero tilt means level. Keep camera roll level. Keep this selected camera position fixed while changing its orientation.
        Preserve the source world's spatial relationships, lighting and visual identities where visible. Subjects may fall outside the new field of view; do not move them to keep them in frame. Infer newly revealed surroundings coherently from the source. Camera controls govern geometry; additional direction cannot override them. The source image is visual authority; saved scene text supplies context, not a new framing or story action.
        """
    }

    static func prompt(spec: LensReframeSpec, parent: ProjectLensHeroImage, settings: ProjectPromptSettingsDocument, model: String, limit: Int? = nil) -> String {
        guard let turn = spec.cameraTurn else { return "" }
        let template = settings.reframeTemplate(mode: templateMode, model: model).body
        let notes = turn.operatorNotes.trimmed
        let context = RosterMentionResolver.strippingMentionTokens(parent.sourcePrompt.trimmed.nilIfEmpty ?? parent.prompt)
        let character = spec.characterName.isEmpty ? "" : "Optional camera-height and embodiment context (text only): \(spec.characterName). \(spec.characterPrompt)"
        let parts = [instructions(spec: spec), template, character,
                     notes.isEmpty ? "" : "Additional creative direction, subordinate to camera geometry:\n\(notes)",
                     context.isEmpty ? "" : "Saved scene context:\n\(context)"]
        let prompt = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return limit.map { String(prompt.prefix(max(instructions(spec: spec).count, $0))) } ?? prompt
    }
}
