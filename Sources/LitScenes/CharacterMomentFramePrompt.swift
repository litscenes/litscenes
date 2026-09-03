import Foundation

/// THE CHARACTER-MOMENT FRAME PROMPT: a character-driven suggestion renders a
/// character ACTING in a place — never an environment plate. Subject matter
/// only; every cast name becomes an `@Name` token so attachments resolve.
struct CharacterMomentFrameCopy: Equatable, Sendable {
    /// "Title · beat" — keeps the card's title split.
    var label: String
    /// The authored prompt with mention tokens; stored as both `prompt` and `sourcePrompt`.
    var sourcePrompt: String
}

enum CharacterMomentFramePrompt {
    static func opener(aspect: String) -> String {
        switch aspect.trimmed.lowercased() {
        case "landscape":
            return "Create one wide cinematic frame of a dramatic moment."
        case "portrait":
            return "Create one tall vertical cinematic frame of a dramatic moment."
        default:
            return "Create one square cinematic frame of a dramatic moment."
        }
    }

    static func compose(
        characterName: String,
        scene: LensAreaScene,
        moment: String,
        validCastNames: [String],
        aspect: String,
        closingLines: [String]
    ) -> CharacterMomentFrameCopy {
        let normalized = scene.normalized()
        let momentText = sentence(moment)
        var lines: [String] = [opener(aspect: aspect)]
        if !momentText.isEmpty {
            lines.append("The moment: \(momentText)")
        }
        // A lead presence that merely repeats the moment would say it twice.
        let cast = normalized.cast.map { entry -> LensSceneCastEntry in
            var value = entry
            if sentence(value.presence).caseInsensitiveCompare(momentText) == .orderedSame {
                value.presence = ""
            }
            return value
        }
        if let castLine = LensSceneCastPrompt.mentionLine(cast: cast, validNames: validCastNames) {
            lines.append(castLine)
        } else if !characterName.trimmed.isEmpty {
            lines.append("Present in this scene: \(token(for: characterName, validNames: validCastNames)).")
        }
        lines.append("The characters are the subject of this frame; the place is where it happens, not what it is about. No one else is present; any other figures are distant and incidental.")
        lines.append(contentsOf: settingLines(normalized.setting, prosePrompt: normalized.prosePrompt))
        lines.append(contentsOf: closingLines)
        let prompt = lines.map(\.trimmed).filter { !$0.isEmpty }.joined(separator: "\n")
        let beat = normalized.storyBeat.trimmed
        let title = normalized.title.trimmed.nilIfEmpty ?? "Moment"
        return CharacterMomentFrameCopy(
            label: beat.isEmpty ? title : "\(title) · \(beat)",
            sourcePrompt: prompt
        )
    }

    /// The setting lines exactly as the scenery builder writes them — minus the
    /// set-dressing block, which belongs to environment plates.
    static func settingLines(_ setting: LensSceneSetting, prosePrompt: String) -> [String] {
        var lines: [String] = []
        if !setting.isEmpty {
            var placeLine = "The place: \(setting.locationName)"
            if !setting.locationType.isEmpty {
                placeLine += " — \(setting.locationType)"
            }
            placeLine += "."
            lines.append(placeLine)
            if !setting.timeOfDay.isEmpty { lines.append("Time: \(setting.timeOfDay).") }
            if !setting.weather.isEmpty { lines.append("Weather: \(setting.weather).") }
            if !setting.spatialLayout.isEmpty { lines.append("Spatial layout: \(setting.spatialLayout).") }
            if !setting.foregroundDetails.isEmpty {
                lines.append("In the foreground: \(setting.foregroundDetails.joined(separator: "; ")).")
            }
            if !setting.backgroundDetails.isEmpty {
                lines.append("In the background: \(setting.backgroundDetails.joined(separator: "; ")).")
            }
            if !setting.notableFeatures.isEmpty {
                lines.append("Notable features: \(setting.notableFeatures.joined(separator: "; ")).")
            }
        } else if !prosePrompt.trimmed.isEmpty {
            lines.append("The place: \(prosePrompt.trimmed)")
        }
        return lines
    }

    private static func token(for name: String, validNames: [String]) -> String {
        let canonical = validNames.map(\.trimmed).first {
            $0.compare(name.trimmed, options: [.caseInsensitive]) == .orderedSame
        }
        return canonical.map { "@\($0)" } ?? name.trimmed
    }

    private static func sentence(_ text: String) -> String {
        var value = text.trimmed
        guard !value.isEmpty else { return "" }
        if let last = value.last, !".!?".contains(last) {
            value += "."
        }
        return value
    }
}
