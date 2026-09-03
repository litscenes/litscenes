import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

@Test func falOutpaintPromptIsBoundedOperatorContentOnly() {
    // FAL Outpaint appends the prompt to its own base outpaint instruction,
    // so the wire carries bounded operator content and nothing of ours.
    let operatorPrompt = Array(
        repeating: "Continue a quiet salt marsh at sunrise with distant reeds and shallow reflective water.",
        count: 12
    ).joined(separator: " ")
    let prompt = falOutpaintProviderPrompt(operatorPrompt, maxCharacters: 500)

    #expect(prompt.count <= 500)
    #expect(prompt.hasPrefix("Continue a quiet salt marsh at sunrise"))
    #expect(!prompt.contains("Never"))
    #expect(!prompt.contains("Extend this exact scene seamlessly"))
}

@Test func falOutpaintEmptyOperatorSendsEmptyPrompt() {
    // An empty prompt is valid per the endpoint contract: its own base
    // instruction drives pure visual continuation.
    #expect(falOutpaintProviderPrompt("", maxCharacters: 500).isEmpty)
    let short = "with collapsed pillars and distant fires beyond the arch"
    #expect(falOutpaintProviderPrompt(short, maxCharacters: 500) == short)
}

@Test func falOutpaintDefaultTemplateCarriesNoSubjectsOrInstructions() {
    let parent = ProjectLensHeroImage(
        imageId: "lens_hero_parent",
        prompt: "final prompt",
        sourcePrompt: "an anonymous traveler kneels in the ruins of an orbital chapel",
        status: "ready"
    )
    let spec = LensReframeSpec(
        mode: LensReframeSpec.zoomOutMode,
        centerX: 0.4,
        centerY: 0.6,
        normalizedWidth: 0.35,
        normalizedHeight: 0.35,
        parentImageId: parent.imageId
    )
    let operatorPrompt = LensReframeComposer.prompt(
        spec: spec,
        parent: parent,
        model: "fal-ai/image-apps-v2/outpaint"
    )
    // The default FAL body adds scenery only: the endpoint reads the prompt
    // as content, so naming the subject would paint a second copy of it.
    #expect(operatorPrompt == "More of the same surroundings continuing in every direction.")
    #expect(!operatorPrompt.contains("traveler"))
    #expect(falOutpaintProviderPrompt(operatorPrompt, maxCharacters: 500) == operatorPrompt)
}

@Test func zoomOutTemplatesDescribeContinuationNotAProtectedInset() {
    // Words that name a discrete rectangle make the models paint one, and
    // negations read as content vocabulary — both are banned.
    let bannedTerms = ["inset", "locked", "protected", "occupies", "margin", "never"]
    for model in ["", "gpt-image-2", "fal-ai/image-apps-v2/outpaint"] {
        let template = ProjectPromptSettingsDocument.builtInTemplate(
            mode: LensReframeSpec.zoomOutMode,
            model: model
        )
        let body = template.body.lowercased()
        for term in bannedTerms {
            #expect(!body.contains(term), "\(template.templateId) still says \(term)")
        }
    }
    let openAI = ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomOutMode,
        model: "gpt-image-2"
    )
    #expect(openAI.body.contains("transparent"))
    #expect(openAI.body.contains("{{original_scene_context}}"))
    let fallback = ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomOutMode,
        model: ""
    )
    #expect(fallback.body.contains("{{original_scene_context}}"))
    // The FAL body is pure additive scenery content — no scene context, which
    // names the subject and would seed a duplicate.
    let fal = ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomOutMode,
        model: "fal-ai/image-apps-v2/outpaint"
    )
    #expect(!fal.body.contains("{{original_scene_context}}"))
}

@Test func storedLegacyZoomOutBodiesYieldToRepairedBuiltIns() {
    let legacyBody = """
    Outpaint the transparent masked perimeter around the locked source image. The protected source occupies {{source_scale_percent}}% of the result and is centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Fill only the new area beyond it: {{margin_left_percent}}% left, {{margin_right_percent}}% right, {{margin_top_percent}}% above, and {{margin_bottom_percent}}% below.

    Make the wider view a seamless continuation of the exact source: continue perspective, geometry, subjects, light direction, palette, materials, weather, depth, and rendering style. Do not alter, duplicate, cover, border, or reframe the protected source.

    Original scene context: {{original_scene_context}}
    """
    var document = ProjectPromptSettingsDocument.empty(projectId: "p1")
    document.reframePrompts = [
        ReframePromptTemplate(
            templateId: "reframe:zoom_out:gpt-image-2",
            mode: LensReframeSpec.zoomOutMode,
            model: "gpt-image-2",
            title: "Zoom Out · GPT Image 2",
            body: legacyBody
        )
    ]
    let resolved = document.reframeTemplate(mode: LensReframeSpec.zoomOutMode, model: "gpt-image-2")
    #expect(!resolved.body.contains("locked source"))
    #expect(resolved.body == ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomOutMode,
        model: "gpt-image-2"
    ).body)

    // An operator-edited body is never migrated away.
    document.reframePrompts[0].body = "My studio's own zoom out language."
    let edited = document.reframeTemplate(mode: LensReframeSpec.zoomOutMode, model: "gpt-image-2")
    #expect(edited.body == "My studio's own zoom out language.")

    // A stored copy of the retired v1 FAL body (context-led) also yields to
    // the current content-only built-in.
    let legacyFALBody = """
    A wider view of this exact scene: {{original_scene_context}}

    The camera pulls back to reveal more of the same place at the same moment. Continue the scenery naturally past every edge of the picture — same light, palette, weather, and rendering style throughout.
    """
    var falDocument = ProjectPromptSettingsDocument.empty(projectId: "p1")
    falDocument.reframePrompts = [
        ReframePromptTemplate(
            templateId: "reframe:zoom_out:fal-ai/image-apps-v2/outpaint",
            mode: LensReframeSpec.zoomOutMode,
            model: "fal-ai/image-apps-v2/outpaint",
            title: "Zoom Out · FAL Outpaint",
            body: legacyFALBody
        )
    ]
    let falResolved = falDocument.reframeTemplate(
        mode: LensReframeSpec.zoomOutMode,
        model: "fal-ai/image-apps-v2/outpaint"
    )
    #expect(falResolved.body == "More of the same surroundings continuing in every direction.")
}

@Test func zoomOutFloorRaisesSliderOnlyAndKeepsLegacySpecsDecodable() {
    // The selectable floor rose to 35%, but persisted 10-30% artifacts keep
    // their original geometry (tolerant-decode law).
    #expect(LensReframeMetrics.zoomOutMinimumSelectableSourceScale == 0.35)
    #expect(LensReframeMetrics.zoomOutMinimumSourceScale == 0.10)
    let legacy = LensReframeSpec(
        mode: LensReframeSpec.zoomOutMode,
        centerX: 0.5,
        centerY: 0.5,
        normalizedWidth: 0.10,
        normalizedHeight: 0.10
    ).normalized()
    #expect(legacy.zoomOutSourceScale == 0.10)
    #expect(abs(legacy.zoomOutSourceRect.width - 0.10) < 0.0001)
}

@Test func lensReframeSpecNormalizedClampsCoordinatesAndDefaultsMode() {
    let spec = LensReframeSpec(
        mode: "  ",
        centerX: 1.4,
        centerY: -0.2,
        normalizedWidth: 2,
        normalizedHeight: -1,
        parentImageId: " parent ",
        characterName: " Mira "
    ).normalized()
    #expect(spec.mode == LensReframeSpec.zoomMode)
    #expect(spec.centerX == 1)
    #expect(spec.centerY == 0)
    #expect(spec.normalizedWidth == 1)
    #expect(spec.normalizedHeight == 0)
    #expect(spec.parentImageId == "parent")
    #expect(spec.characterName == "Mira")
    #expect(!spec.isViewpoint)
}

@Test func lensReframeSpecDecodesWithMissingKeys() throws {
    let spec = try JSONDecoder().decode(LensReframeSpec.self, from: Data("{}".utf8))
    #expect(spec.mode == LensReframeSpec.zoomMode)
    #expect(spec.centerX == 0.5)
    #expect(spec.centerY == 0.5)
    #expect(spec.viewDirection == LensReframeViewDirection.north.rawValue)
    #expect(spec.parentImageId.isEmpty)
}

@Test func lensHeroImageWithoutReframeKeyDecodes() throws {
    let json = """
    {"imageId": "lens_hero_test", "status": "ready", "imagePath": "/tmp/a.png"}
    """
    let image = try JSONDecoder().decode(ProjectLensHeroImage.self, from: Data(json.utf8))
    #expect(image.imageId == "lens_hero_test")
    #expect(image.reframe == nil)
}

@Test func lensHeroImageMalformedReframeDegradesToNil() throws {
    let json = """
    {"imageId": "lens_hero_test", "reframe": "not-an-object"}
    """
    let image = try JSONDecoder().decode(ProjectLensHeroImage.self, from: Data(json.utf8))
    #expect(image.imageId == "lens_hero_test")
    #expect(image.reframe == nil)
}

@Test func lensHeroImageReframeRoundTrips() throws {
    var image = ProjectLensHeroImage(imageId: "lens_hero_child", status: "ready")
    image.reframe = LensReframeSpec(
        mode: LensReframeSpec.viewpointMode,
        centerX: 0.62,
        centerY: 0.41,
        normalizedWidth: 0.1,
        normalizedHeight: 0.1,
        viewDirection: LensReframeViewDirection.east.rawValue,
        parentImageId: "lens_hero_parent",
        characterId: "char_1",
        characterName: "Mira",
        characterPrompt: "a wiry sailor in oilskins"
    )
    let data = try JSONEncoder().encode(image)
    let decoded = try JSONDecoder().decode(ProjectLensHeroImage.self, from: data)
    #expect(decoded.reframe?.isViewpoint == true)
    #expect(decoded.reframe?.viewDirection == LensReframeViewDirection.east.rawValue)
    #expect(decoded.reframe?.parentImageId == "lens_hero_parent")
    #expect(decoded.reframe?.characterName == "Mira")
    #expect(decoded.reframe?.centerX == 0.62)
}

@Test func lensReframeSpecDecodesLegacyModeAliases() {
    let zoom = LensReframeSpec(mode: LensReframeSpec.observerZoomMode).normalized()
    let viewpoint = LensReframeSpec(mode: LensReframeSpec.characterPOVMode).normalized()
    #expect(zoom.mode == LensReframeSpec.zoomMode)
    #expect(viewpoint.mode == LensReframeSpec.viewpointMode)
}

@Test func lensReframeFocusRectIs16By9CentersAndPins() {
    let size = CGSize(width: 1000, height: 500)
    let centered = lensReframeFocusRect(center: CGPoint(x: 0.5, y: 0.5), imagePixelSize: size)
    #expect(abs(centered.midX - 0.5) < 0.0001)
    #expect(abs(centered.midY - 0.5) < 0.0001)
    // Base width 160px → 160/1000 = 0.16; height 160*9/16 = 90px → 90/500 = 0.18.
    #expect(abs(centered.width - 0.16) < 0.0001)
    #expect(abs(centered.height - 0.18) < 0.0001)
    // The reticle is 16:9 in source pixels.
    let widthPixels = centered.width * size.width
    let heightPixels = centered.height * size.height
    #expect(abs(widthPixels / heightPixels - 16.0 / 9.0) < 0.0001)

    let pinned = lensReframeFocusRect(center: CGPoint(x: 0, y: 1), imagePixelSize: size)
    #expect(pinned.minX == 0)
    #expect(abs(pinned.maxY - 1) < 0.0001)
    #expect(abs(pinned.width - 0.16) < 0.0001)

    #expect(lensReframeFocusRect(center: CGPoint(x: 0.5, y: 0.5), imagePixelSize: .zero) == .zero)
}

@Test func lensReframeCropRectIs16By9AndStaysInsideImage() {
    let size = CGSize(width: 1000, height: 500)
    let spec = LensReframeSpec(centerX: 0.5, centerY: 0.5)
    let crop = lensReframeCropRect(imagePixelSize: size, spec: spec)
    // Base width 160 × balanced scale 2 = 320 wide; 320 ÷ 16:9 = 180 tall.
    #expect(crop.width == 320)
    #expect(crop.height == 180)
    #expect(crop.midX == 500)
    #expect(crop.midY == 250)

    let cornerSpec = LensReframeSpec(centerX: 0, centerY: 0)
    let cornerCrop = lensReframeCropRect(imagePixelSize: size, spec: cornerSpec)
    #expect(cornerCrop.minX == 0)
    #expect(cornerCrop.minY == 0)
    #expect(cornerCrop.width == 320)

    // A small image bounds the crop width to what a 16:9 rect can hold.
    let tinyCrop = lensReframeCropRect(imagePixelSize: CGSize(width: 120, height: 90), spec: spec)
    #expect(tinyCrop.width == 120)
    #expect(abs(tinyCrop.width / tinyCrop.height - 16.0 / 9.0) < 0.05)
}

@Test func lensReframeZoomPromptIsCondensedAndCoordinatesRideDescriptorsOnly() {
    let parent = ProjectLensHeroImage(
        imageId: "lens_hero_parent",
        prompt: "final prompt",
        sourcePrompt: "a harbor town at dusk",
        status: "ready"
    )
    let spec = LensReframeSpec(
        centerX: 0.62,
        centerY: 0.41,
        normalizedWidth: 0.32,
        normalizedHeight: 0.36,
        parentImageId: parent.imageId
    )
    // The editable zoom body is short instructions only: no coordinate
    // percentages and no inline scene-context dump — both live in the
    // attachment descriptors the runner always appends.
    for model in ["", "gpt-image-2", "fal-ai/flux-2-pro/edit", "fal-ai/nano-banana-2/edit"] {
        let prompt = LensReframeComposer.prompt(spec: spec, parent: parent, model: model)
        #expect(!prompt.contains("%"), "zoom body for '\(model)' still carries numbers")
        #expect(!prompt.contains("a harbor town at dusk"), "zoom body for '\(model)' still dumps scene context")
        #expect(prompt.count < 400, "zoom body for '\(model)' is no longer condensed (\(prompt.count) chars)")
    }
    let prompt = LensReframeComposer.prompt(spec: spec, parent: parent)
    #expect(prompt.contains("entire new frame"))

    let descriptor = LensReframeComposer.attachmentDescriptor(spec: spec)
    #expect(descriptor.contains("REFRAME source crop"))
    #expect(descriptor.contains("centered 62% from the left and 41% from the top"))
    // Balanced fidelity pads the crop 2×, so the selection is its central 50%.
    #expect(descriptor.contains("central 50%"))

    let tightSpec = LensReframeSpec(
        centerX: 0.62,
        centerY: 0.41,
        normalizedWidth: 0.32,
        normalizedHeight: 0.36,
        parentImageId: parent.imageId,
        fidelity: "tight"
    )
    // 1/1.3 ≈ 77% for TIGHT; 1/3 ≈ 33% for WIDE.
    #expect(LensReframeComposer.selectionPercentOfCrop(spec: tightSpec) == 77)
    #expect(LensReframeComposer.attachmentDescriptor(spec: tightSpec).contains("central 77%"))
    var wideSpec = tightSpec
    wideSpec.fidelity = "wide"
    #expect(LensReframeComposer.selectionPercentOfCrop(spec: wideSpec) == 33)
}

@Test func lensReframeViewpointPromptCarriesCharacterDirectionAndCoordinates() {
    let parent = ProjectLensHeroImage(
        imageId: "lens_hero_parent",
        sourcePrompt: "a harbor town at dusk",
        status: "ready"
    )
    let spec = LensReframeSpec(
        mode: LensReframeSpec.viewpointMode,
        centerX: 0.25,
        centerY: 0.75,
        viewDirection: LensReframeViewDirection.east.rawValue,
        parentImageId: parent.imageId,
        characterName: "Mira",
        characterPrompt: "a wiry sailor in oilskins"
    )
    let prompt = LensReframeComposer.prompt(spec: spec, parent: parent)
    #expect(prompt.contains("camera at the selected point"))
    #expect(prompt.contains("toward the right side of the source frame"))
    #expect(prompt.contains("Mira: a wiry sailor in oilskins"))
    #expect(prompt.contains("25% from the left"))
    #expect(prompt.contains("75% from the top"))

    let descriptor = LensReframeComposer.attachmentDescriptor(spec: spec)
    #expect(descriptor.contains("REFRAME source frame"))
    #expect(descriptor.contains("looking toward the right side of the source frame"))
    #expect(descriptor.contains("25% from the left"))
}

@Test func lensReframeCastCandidateCompositePromptFoldsPropsAndAffinity() {
    let candidate = LensReframeCastCandidate(
        id: "char_1",
        name: "Mira",
        prompt: "a wiry sailor in oilskins",
        signatureProps: ["brass spyglass", "rope belt"],
        environmentAffinity: "the harbor docks"
    )
    #expect(candidate.compositePrompt.contains("a wiry sailor in oilskins"))
    #expect(candidate.compositePrompt.contains("brass spyglass"))
    #expect(candidate.compositePrompt.contains("the harbor docks"))

    let bare = LensReframeCastCandidate(
        id: "char_2",
        name: "Jonas",
        prompt: "a lighthouse keeper",
        signatureProps: [],
        environmentAffinity: ""
    )
    #expect(bare.compositePrompt == "a lighthouse keeper")
}

@Test func reframeFidelityIsTolerantAndScalesTheCrop() throws {
    // Absent / unknown fidelity normalizes to balanced ("true").
    let legacy = try JSONDecoder().decode(LensReframeSpec.self, from: Data(#"{"mode":"zoom"}"#.utf8))
    #expect(legacy.resolvedFidelity == .balanced)
    var spec = LensReframeSpec(mode: LensReframeSpec.zoomMode, centerX: 0.5, centerY: 0.5, fidelity: "nonsense")
    #expect(spec.normalized().resolvedFidelity == .balanced)
    spec.fidelity = "tight"
    #expect(spec.normalized().resolvedFidelity == .tight)

    // Tighter fidelity → smaller generation crop; wider → larger.
    let size = CGSize(width: 2000, height: 1200)
    let tight = lensReframeCropRect(
        imagePixelSize: size,
        spec: LensReframeSpec(mode: LensReframeSpec.zoomMode, centerX: 0.5, centerY: 0.5, fidelity: "tight")
    )
    let balanced = lensReframeCropRect(
        imagePixelSize: size,
        spec: LensReframeSpec(mode: LensReframeSpec.zoomMode, centerX: 0.5, centerY: 0.5, fidelity: "true")
    )
    let wide = lensReframeCropRect(
        imagePixelSize: size,
        spec: LensReframeSpec(mode: LensReframeSpec.zoomMode, centerX: 0.5, centerY: 0.5, fidelity: "wide")
    )
    #expect(tight.width < balanced.width)
    #expect(balanced.width < wide.width)
    // Explicit override still wins.
    let overridden = lensReframeCropRect(
        imagePixelSize: size,
        spec: LensReframeSpec(mode: LensReframeSpec.zoomMode, centerX: 0.5, centerY: 0.5, fidelity: "wide"),
        contextScale: 1.0
    )
    #expect(overridden.width < wide.width)
}

@Test func lensReframeRotationDecodesAndNormalizesTolerantly() throws {
    // Absent key → level (tolerant-decode law).
    let legacy = try JSONDecoder().decode(LensReframeSpec.self, from: Data("{}".utf8))
    #expect(legacy.rotationDegrees == 0)

    // An explicit angle round-trips.
    var spec = LensReframeSpec(mode: LensReframeSpec.zoomMode, rotationDegrees: 30)
    let data = try JSONEncoder().encode(spec)
    let decoded = try JSONDecoder().decode(LensReframeSpec.self, from: data)
    #expect(decoded.rotationDegrees == 30)

    // Out-of-range clamps to ±45; hygiene band snaps to level.
    spec.rotationDegrees = 9999
    #expect(spec.normalized().rotationDegrees == 45)
    spec.rotationDegrees = -9999
    #expect(spec.normalized().rotationDegrees == -45)
    spec.rotationDegrees = 0.3
    #expect(spec.normalized().rotationDegrees == 0)

    // Viewpoint keeps its tilt; zoom_out has no reticle and forces level.
    let viewpoint = LensReframeSpec(mode: LensReframeSpec.viewpointMode, rotationDegrees: 20).normalized()
    #expect(viewpoint.rotationDegrees == 20)
    let zoomOut = LensReframeSpec(mode: LensReframeSpec.zoomOutMode, rotationDegrees: 20).normalized()
    #expect(zoomOut.rotationDegrees == 0)

    // Type garbage in the field degrades the whole spec to nil at the document
    // level — the same tolerance contract as every other field.
    let json = """
    {"imageId": "lens_hero_test", "reframe": {"mode": "zoom", "rotationDegrees": "sideways"}}
    """
    let image = try JSONDecoder().decode(ProjectLensHeroImage.self, from: Data(json.utf8))
    #expect(image.reframe == nil)
}

@Test func lensReframeRotatedFocusRectKeepsEveryTiltedCornerInside() {
    // The returned rect is the UNROTATED footprint; the real selection is that
    // rect rotated about its center in PIXEL space. All four tilted corners
    // must stay inside the image for every angle, size, and click position.
    let sizes = [CGSize(width: 1000, height: 500), CGSize(width: 500, height: 1000), CGSize(width: 120, height: 90)]
    let centers = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.05, y: 0.9)]
    for size in sizes {
        for center in centers {
            for degrees in [15.0, 30.0, 45.0, -30.0] {
                let rect = lensReframeFocusRect(
                    center: center,
                    imagePixelSize: size,
                    edgePixels: 600,
                    rotationDegrees: degrees
                )
                #expect(!rect.isEmpty)
                let radians = degrees * .pi / 180
                let widthPx = rect.width * size.width
                let heightPx = rect.height * size.height
                // 16:9 in source pixels survives rotation.
                #expect(abs(widthPx / heightPx - 16.0 / 9.0) < 0.001)
                let centerPx = CGPoint(x: rect.midX * size.width, y: rect.midY * size.height)
                for sx in [-0.5, 0.5] {
                    for sy in [-0.5, 0.5] {
                        let dx = widthPx * sx
                        let dy = heightPx * sy
                        // Clockwise-positive rotation in top-left image space.
                        let cornerX = centerPx.x + dx * cos(radians) - dy * sin(radians)
                        let cornerY = centerPx.y + dx * sin(radians) + dy * cos(radians)
                        #expect(cornerX >= -0.01 && cornerX <= size.width + 0.01,
                                "corner x \(cornerX) escapes \(size) at \(degrees)° from \(center)")
                        #expect(cornerY >= -0.01 && cornerY <= size.height + 0.01,
                                "corner y \(cornerY) escapes \(size) at \(degrees)° from \(center)")
                    }
                }
            }
        }
    }

    // Level output is unchanged by the rotation-aware math (regression lock).
    let size = CGSize(width: 1000, height: 500)
    let level = lensReframeFocusRect(center: CGPoint(x: 0.5, y: 0.5), imagePixelSize: size, rotationDegrees: 0)
    #expect(abs(level.width - 0.16) < 0.0001)
    #expect(abs(level.height - 0.18) < 0.0001)
}

@Test func lensReframeRotatedCropCapsWidthToTheTiltedFit() {
    let size = CGSize(width: 1000, height: 500)
    var spec = LensReframeSpec(
        mode: LensReframeSpec.zoomMode,
        centerX: 0.5,
        centerY: 0.5,
        normalizedWidth: 0.32,
        normalizedHeight: 0.36
    )

    // Level, balanced fidelity: 320px reticle × 2 = 640 wide, fits.
    let levelCrop = lensReframeCropRect(imagePixelSize: size, spec: spec)
    #expect(levelCrop.width == 640)

    // At 45° the tilted 16:9 crop's bounding box must fit the 500px height:
    // max width = (500 − 2) / (sin45 + cos45 ÷ (16/9)) ≈ 450.7 — the effective
    // context scale shrinks to what fits.
    spec.rotationDegrees = 45
    let tiltedCrop = lensReframeCropRect(imagePixelSize: size, spec: spec)
    #expect(tiltedCrop.width < 452)
    #expect(tiltedCrop.width > 449)
    // The tilted crop's bounding box stays inside the image.
    let radians = 45.0 * .pi / 180
    let centerPx = CGPoint(x: tiltedCrop.midX, y: tiltedCrop.midY)
    let halfX = tiltedCrop.width / 2 * abs(cos(radians)) + tiltedCrop.height / 2 * abs(sin(radians))
    let halfY = tiltedCrop.width / 2 * abs(sin(radians)) + tiltedCrop.height / 2 * abs(cos(radians))
    #expect(centerPx.x - halfX >= 0)
    #expect(centerPx.x + halfX <= size.width)
    #expect(centerPx.y - halfY >= 0)
    #expect(centerPx.y + halfY <= size.height)
}

@Test func lensReframeSnappedRotationSnapsDetentsAndClamps() {
    // Magnetic level band without Shift.
    #expect(lensReframeSnappedRotation(rawDegrees: 1.2, shiftDown: false) == 0)
    #expect(lensReframeSnappedRotation(rawDegrees: -1.4, shiftDown: false) == 0)
    // Beyond the band the raw angle rides through.
    #expect(lensReframeSnappedRotation(rawDegrees: 22, shiftDown: false) == 22)
    #expect(lensReframeSnappedRotation(rawDegrees: 8, shiftDown: false) == 8)
    // Shift quantizes to 15° detents.
    #expect(lensReframeSnappedRotation(rawDegrees: 8, shiftDown: true) == 15)
    #expect(lensReframeSnappedRotation(rawDegrees: -8, shiftDown: true) == -15)
    #expect(lensReframeSnappedRotation(rawDegrees: 3, shiftDown: true) == 0)
    // The ±45 range holds either way.
    #expect(lensReframeSnappedRotation(rawDegrees: 50, shiftDown: false) == 45)
    #expect(lensReframeSnappedRotation(rawDegrees: -50, shiftDown: false) == -45)
    #expect(lensReframeSnappedRotation(rawDegrees: 50, shiftDown: true) == 45)
    #expect(lensReframeSnappedRotation(rawDegrees: .nan, shiftDown: false) == 0)
}

@Test func lensReframeRotationRidesPromptsAndDescriptors() {
    let parent = ProjectLensHeroImage(
        imageId: "lens_hero_parent",
        sourcePrompt: "a harbor town at dusk",
        status: "ready"
    )

    // Zoom: the default body's clause names the tilt and the straightened crop.
    let tilted = LensReframeSpec(
        mode: LensReframeSpec.zoomMode,
        centerX: 0.5,
        centerY: 0.5,
        normalizedWidth: 0.32,
        normalizedHeight: 0.36,
        parentImageId: parent.imageId,
        rotationDegrees: 12
    )
    let prompt = LensReframeComposer.prompt(spec: tilted, parent: parent, model: "gpt-image-2")
    #expect(prompt.contains("tilted 12° clockwise"))
    #expect(prompt.contains("straightened"))

    // Level specs render no rotation language at all.
    var level = tilted
    level.rotationDegrees = 0
    let levelPrompt = LensReframeComposer.prompt(spec: level, parent: parent, model: "gpt-image-2")
    #expect(!levelPrompt.contains("tilted"))
    #expect(!levelPrompt.contains("straightened"))

    // Viewpoint reads as a camera roll, counterclockwise for negative angles.
    let viewpoint = LensReframeSpec(
        mode: LensReframeSpec.viewpointMode,
        centerX: 0.25,
        centerY: 0.75,
        viewDirection: LensReframeViewDirection.east.rawValue,
        parentImageId: parent.imageId,
        rotationDegrees: -20
    )
    let viewpointPrompt = LensReframeComposer.prompt(spec: viewpoint, parent: parent, model: "gpt-image-2")
    #expect(viewpointPrompt.contains("Roll the new camera 20° counterclockwise"))

    // The attachment descriptors are the always-appended channel: they carry
    // the tilt even when the operator hand-edited the prompt body.
    let cropDescriptor = LensReframeComposer.focusCropAttachmentDescriptor(spec: tilted)
    #expect(cropDescriptor.contains("STRAIGHTENED"))
    #expect(cropDescriptor.contains("tilted 12° clockwise"))
    let levelCropDescriptor = LensReframeComposer.focusCropAttachmentDescriptor(spec: level)
    #expect(!levelCropDescriptor.contains("STRAIGHTENED"))
    #expect(LensReframeComposer.fullFrameAttachmentDescriptor(spec: tilted).contains("tilted 12° clockwise"))
    #expect(!LensReframeComposer.fullFrameAttachmentDescriptor(spec: level).contains("tilted"))
    #expect(LensReframeComposer.compositeAttachmentDescriptor(spec: tilted).contains("STRAIGHTENED"))
    #expect(LensReframeComposer.fullFrameAttachmentDescriptor(spec: viewpoint).contains("Roll the new camera 20° counterclockwise"))
}

@Test func storedLegacyZoomAndViewpointBodiesYieldToCurrentBuiltIns() {
    // A stored copy of the pre-rotation zoom body is a stale saved default,
    // not an operator edit; the repaired built-in (with the rotation clause
    // token) wins.
    let legacyZoomBody = """
    Zoom into the selected source region. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. The new image IS that rectangle, edge-to-edge — match its framing and magnification exactly, not as a small detail and not pulled back wider.

    Preserve source-world geography, recurring subjects, palette, lighting, material texture, and rendering style. Sharpen and complete visible detail without inventing foreign objects or changing the scene premise.

    Original scene context: {{original_scene_context}}
    """
    var document = ProjectPromptSettingsDocument.empty(projectId: "p1")
    document.reframePrompts = [
        ReframePromptTemplate(
            templateId: "reframe:zoom:gpt-image-2",
            mode: LensReframeSpec.zoomMode,
            model: "gpt-image-2",
            title: "Zoom · GPT Image 2",
            body: legacyZoomBody
        )
    ]
    let resolved = document.reframeTemplate(mode: LensReframeSpec.zoomMode, model: "gpt-image-2")
    #expect(resolved.body.contains("{{focus_rotation_clause}}"))
    #expect(resolved.body == ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomMode,
        model: "gpt-image-2"
    ).body)

    // A stored rotation-era verbose body (coordinates + inline scene context)
    // is likewise a stale saved default: the condensed built-in wins.
    let verboseRotationBody = """
    Zoom into the selected source region. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. The new image IS that rectangle, edge-to-edge — match its framing and magnification exactly, not as a small detail and not pulled back wider. {{focus_rotation_clause}}

    Preserve source-world geography, recurring subjects, palette, lighting, material texture, and rendering style. Sharpen and complete visible detail without inventing foreign objects or changing the scene premise.

    Original scene context: {{original_scene_context}}
    """
    document.reframePrompts[0].body = verboseRotationBody
    let condensed = document.reframeTemplate(mode: LensReframeSpec.zoomMode, model: "gpt-image-2")
    #expect(!condensed.body.contains("{{focus_width_percent}}"))
    #expect(!condensed.body.contains("{{original_scene_context}}"))
    #expect(condensed.body == ProjectPromptSettingsDocument.builtInTemplate(
        mode: LensReframeSpec.zoomMode,
        model: "gpt-image-2"
    ).body)

    // An operator-edited body is never migrated away.
    document.reframePrompts[0].body = "My studio's own zoom language."
    let edited = document.reframeTemplate(mode: LensReframeSpec.zoomMode, model: "gpt-image-2")
    #expect(edited.body == "My studio's own zoom language.")

    // Same repair for the viewpoint fallback.
    let legacyViewpointBody = """
    Viewpoint reframe from inside the source render. Place the camera at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, then look {{view_direction}}.

    The output is a new camera angle from that point, not a crop of the original frame. Preserve source-world geography, time of day, weather, lighting, palette, and rendering style.{{character_context}}

    Original scene context: {{original_scene_context}}
    """
    var viewpointDocument = ProjectPromptSettingsDocument.empty(projectId: "p1")
    viewpointDocument.reframePrompts = [
        ReframePromptTemplate(
            templateId: "reframe:viewpoint:fallback",
            mode: LensReframeSpec.viewpointMode,
            model: "",
            title: "Viewpoint fallback",
            body: legacyViewpointBody
        )
    ]
    let viewpointResolved = viewpointDocument.reframeTemplate(mode: LensReframeSpec.viewpointMode, model: "")
    #expect(viewpointResolved.body.contains("{{focus_rotation_clause}}"))
}

/// Solid-quadrant source for the straightening test: TL red, TR green,
/// BL blue, BR white (top-left image coordinates).
private func lensReframeTestQuadrantImage(width: Int, height: Int) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }
    let w = CGFloat(width)
    let h = CGFloat(height)
    // The context is y-up: the image's top half is the upper half of CG space.
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))
    return context.makeImage()
}

/// RGB of the pixel at top-left-origin (x, y).
private func lensReframeTestPixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard x >= 0, y >= 0, x < image.width, y < image.height,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: image.width,
              height: image.height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }
    // Bitmap-context memory is top-down: buffer row 0 is the top scanline.
    let offset = y * context.bytesPerRow + x * 4
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
}

@Test func lensReframeExtractCropStraightensTheTiltedSelection() throws {
    let source = try #require(lensReframeTestQuadrantImage(width: 400, height: 300))

    // Level extraction takes the exact cropping fast path.
    let levelRect = CGRect(x: 60, y: 40, width: 160, height: 90)
    let level = try #require(lensReframeExtractCrop(from: source, cropRect: levelRect, rotationDegrees: 0))
    let direct = try #require(source.cropping(to: levelRect))
    #expect(level.width == direct.width)
    #expect(level.height == direct.height)
    // Fully inside the top-left quadrant → solid red. (Dominant-channel
    // thresholds: the generic-RGB fills shift a little when converted to the
    // sRGB context — "pure" blue lands at (4, 51, 255).)
    let levelPixel = try #require(lensReframeTestPixel(level, x: 80, y: 45))
    #expect(levelPixel.r > 200 && levelPixel.g < 80 && levelPixel.b < 80)

    // A 30°-tilted crop centered on the quadrant intersection, straightened.
    // A point at local offset d from the output center samples the source at
    // center + R(30°)·d (clockwise-positive, top-left image space).
    let tiltedRect = CGRect(x: 120, y: 105, width: 160, height: 90)
    let tilted = try #require(lensReframeExtractCrop(from: source, cropRect: tiltedRect, rotationDegrees: 30))
    #expect(tilted.width == 160)
    #expect(tilted.height == 90)

    // Local (+60, 0): source (200 + 60·cos30, 150 + 60·sin30) = (252, 180) —
    // right of and below the intersection → the BR quadrant, white.
    let right = try #require(lensReframeTestPixel(tilted, x: 80 + 60, y: 45))
    #expect(right.r > 200 && right.g > 200 && right.b > 200)

    // Local (−60, 0): source (148, 120) → TL quadrant, red.
    let left = try #require(lensReframeTestPixel(tilted, x: 80 - 60, y: 45))
    #expect(left.r > 200 && left.g < 80 && left.b < 80)

    // Local (0, +30) (down in the output): source (200 − 30·sin30, 150 + 30·cos30)
    // = (185, 176) → BL quadrant, blue.
    let below = try #require(lensReframeTestPixel(tilted, x: 80, y: 45 + 30))
    #expect(below.b > 200 && below.r < 80 && below.g < 80)

    // Local (0, −30) (up in the output): source (215, 124) → TR quadrant, green.
    let above = try #require(lensReframeTestPixel(tilted, x: 80, y: 45 - 30))
    #expect(above.g > 200 && above.r < 80 && above.b < 80)
}
