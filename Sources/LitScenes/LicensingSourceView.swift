import SwiftUI

struct LicensingSourceView: View {
    private let identity = LitScenesReleaseIdentity.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(identity.displayName)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(identity.licenseLabel)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                legalSection(
                    "This build",
                    text: buildExplanation
                )

                if let sourceURL = identity.correspondingSourceURL {
                    legalSection(
                        "Corresponding Source",
                        text: identity.sourceRevision.map { "Exact source revision: \($0)" }
                            ?? "The exact source revision is identified by the linked source archive."
                    )
                    Link("Open exact Corresponding Source", destination: sourceURL)
                } else if identity.channel == .development {
                    legalSection(
                        "Not a release",
                        text: "Development builds are local, unsigned release candidates. They are not the AGPL community distribution or the official commercial distribution."
                    )
                    Link("Public Desktop project", destination: LitScenesReleaseIdentity.publicRepositoryURL)
                }

                legalSection(
                    "Brand",
                    text: "The LitScenes name, logo, icon, and official-build identity are reserved marks. Modified distributions must use a distinct name, bundle identifier, and non-confusing branding unless authorized. Exact unmodified redistribution, nominative reference, and statutory uses are unaffected."
                )

                legalSection(
                    "Hosted services",
                    text: "Hosted generation, SMS, billing, orchestration, curated catalogs, and support are separate services operated by Oʻahu Mushrooms LLC d/b/a Oʻahu A.I. unless a service states otherwise. They are not granted by the Desktop source license."
                )

                Link("Catalog terms", destination: LitScenesReleaseIdentity.catalogTermsURL)
                Link("Desktop licensing", destination: URL(string: "https://litscenes.ai/licensing/")!)
                Link("Commercial licensing", destination: URL(string: "https://litscenes.ai/commercial/")!)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 520, idealHeight: 620)
    }

    private var buildExplanation: String {
        switch identity.channel {
        case .community:
            return "LitScenes Community is distributed under GNU AGPL version 3 only. Commercial use, sale, and redistribution are permitted when the AGPL is followed. A separate commercial license is available for proprietary distribution or other use that does not comply with AGPL-3.0-only."
        case .officialCommercial:
            return "This official build is distributed by the rights holder under its accompanying commercial EULA. Open-source components remain subject to their own notices."
        case .development:
            return "This local development build has an isolated identity and data directory so it cannot be mistaken for a released community or official build."
        }
    }

    private func legalSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct LitScenesLicensingCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Licensing & Source…") {
                openWindow(id: "licensing-source")
            }
        }
    }
}
