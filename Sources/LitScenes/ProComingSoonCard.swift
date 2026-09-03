import SwiftUI

/// The "LitScenes Pro — Coming soon" interest card. Pro is the hosted story
/// service under its public name, so every face says both once. The card is
/// informational: a native `Link` to the public signup, no request on display,
/// no address collected in the app. Gated by
/// `LitScenesReleaseIdentity.showsProInterestPromotion` at every call site.
struct ProComingSoonCard: View {
    enum Face {
        /// Welcome and Settings: eyebrow, three points, the link, a disclosure.
        case card
        /// The STORY composer: one honest line about Direct mode, dismissible.
        case line
    }

    enum Surface {
        /// Dark chrome (Welcome, Settings).
        case dark
        /// The light-forced paper column (STORY).
        case paper
    }

    var face: Face = .card
    var surface: Surface = .dark
    /// `.line` only: hides the line for this launch.
    var onDismiss: () -> Void = {}

    private static let points = [
        "Literature-informed Story Graph",
        "White-glove project setup",
        "Midjourney-ready prompt & SREF workflows",
    ]

    private var titleInk: Color { surface == .dark ? CanonColor.bone : CanonColor.ink }
    private var bodyInk: Color { surface == .dark ? CanonColor.muted : CanonColor.ink.opacity(0.58) }
    private var fill: Color { surface == .dark ? CanonColor.mediaCard : CanonColor.paperInset.opacity(0.5) }
    private var stroke: Color { surface == .dark ? CanonColor.hairlineDark.opacity(0.7) : CanonColor.hairlinePaper }

    var body: some View {
        switch face {
        case .card: cardFace
        case .line: lineFace
        }
    }

    private var cardFace: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("LITSCENES PRO")
                    .font(CanonType.archive(10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.brass)
                Spacer()
                Text("COMING SOON")
                    .font(CanonType.archive(10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(bodyInk)
            }
            Text("The hosted story service, under its public name.")
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(titleInk)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Self.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·")
                        Text(point)
                    }
                    .font(CanonType.interface(11))
                    .foregroundStyle(bodyInk)
                }
            }
            notifyLink
                .padding(.top, 2)
            Text("Opens litscenes.ai. Third-party accounts and terms apply.")
                .font(CanonType.interface(10))
                .foregroundStyle(bodyInk.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke))
    }

    private var lineFace: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Direct mode · bundled starter vocabulary. LitScenes Pro — the hosted story service — adds the literature-informed Story Graph.")
                .font(CanonType.interface(11))
                .foregroundStyle(bodyInk)
                .fixedSize(horizontal: false, vertical: true)
            notifyLink
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Hide until the next launch")
            .accessibilityLabel("Hide the LitScenes Pro note until the next launch")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke))
    }

    private var notifyLink: some View {
        Link("Get notified →", destination: LitScenesReleaseIdentity.proInterestURL)
            .font(CanonType.interface(12, weight: .semibold))
            .foregroundStyle(CanonColor.brass)
            .help("Opens litscenes.ai in your browser")
            .accessibilityLabel("Get notified about LitScenes Pro, opens litscenes.ai")
    }
}
