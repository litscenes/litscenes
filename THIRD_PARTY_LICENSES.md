# Third-party licenses and asset inventory

This inventory applies to the public Desktop source export. It is not a substitute for the complete license text shipped by each dependency.

| Component | Version/source | License | Distribution notes |
| --- | --- | --- | --- |
| Yams | 5.4.0, `github.com/jpsim/Yams` | MIT | Resolved by SwiftPM; upstream license is included in the checkout/artifact as required. |
| PhosphorSwift / selected Phosphor icons | upstream 2.1.0 subset | MIT | Vendored subset under `Vendor/PhosphorSwift`; its MIT license is included beside the source. |
| Apple system frameworks | macOS SDK | Apple platform terms | Dynamically supplied by macOS; not copied into this repository. |
| LitScenes Community icon | editable SVG and generated PNG | AGPL-3.0-only copyright; separate trademark policy | May identify the exact project-issued Community package; modified distributions should replace it. |
| Code of Conduct text | Contributor Covenant 2.1, `contributor-covenant.org` | CC BY 4.0 | `CODE_OF_CONDUCT.md`; full license text in `LICENSES/CC-BY-4.0.txt`. |
| Aesthetic term vocabulary (part of `Sources/LitScenes/Resources/meaning_choice_index.json`) | term list derived from the community-maintained Aesthetics Wiki, `aesthetics.fandom.com` | CC BY-SA 3.0 | Term names only, curated and capped; the accompanying prose definitions are original. Full license text in `LICENSES/CC-BY-SA-3.0.txt`. |
| Fraunces display serif (three static TTFs: 72pt Regular, SemiBold, Italic) | 1.000, `github.com/undercasetype/Fraunces` | SIL OFL 1.1 | Bundled under `Sources/LitScenes/Resources/Fonts` with the upstream `OFL.txt` beside the files; full license text in `LICENSES/OFL-1.1.txt`. Reserved-name terms respected: files ship unmodified under their original names. |

## Not present in the public export

The export must not contain the official LitScenes icon, private aesthetic images/catalogs, private prompts or style graph, user media, generated renders, model weights, fonts beyond the OFL-licensed Fraunces statics inventoried above, sample media, signing material, credentials, telemetry, or hosted-service source.

Before each public release, the release owner must review `Package.resolved`, vendored sources, bundled resources, Git diff, and the export manifest. A dependency or asset whose terms or provenance are uncertain is a release blocker.
