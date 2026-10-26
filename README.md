# LitScenes

A free, open-source macOS app for stories longer than a prompt. Built with Aloha by [Oʻahu A.I.](https://oahu.ai).

https://github.com/user-attachments/assets/0c371be6-f1b8-4f61-ad32-45be4e5ae80b

## A letter from the maker

I built LitScenes because I wanted to make videos that hold together as stories — across scenes, across characters, across whole projects. The app builds meaning and structure first; frames and renders follow from them.

LitScenes is a personal creative tool, and the code is yours to study and improve. It runs on your Mac with a complete, editable meaning graph and local projects. There is no LitScenes account or subscription. When you choose to generate, you use your own provider accounts and pay those providers for their usage.

If LitScenes helps you drive a good story into the world, I would be delighted. That is the point.

Kevin Riggen

## What you can make

- **A story with a spine.** A Goal interview establishes the purpose, Frame Context grounds it in your material, Scene Stories organize the action, and Frame Forms develop concrete frames.
- **Scenes, shots, and cuts.** Arrange footage and generated frames, shape trims, seams, loops, narration and sound, then assemble and export locally.
- **A personal visual language.** Browse 26 bundled starter styles, use your own reference images, and keep recurring people and places coherent across scenes.
- **Meaning you can inspect and change.** The complete graph includes themes, tensions, situations, symbols, motifs, claims, moods, transformations, genre forces, beats and scene roles. Import YAML packs or add project overlays without changing saved work.
- **Your own workspace.** Projects, media, credentials and inference traces live on your Mac. No telemetry, account service, catalog service or hosted database is required. Provider requests use your configured accounts; graph updates are an explicit GitHub download.

## Install from source

Requires macOS 15+, Swift 6.1+ and a macOS 15+ SDK (Xcode 16.3+ or compatible Command Line Tools).

Download and inspect the installer from this repository:

```sh
curl -fSL https://raw.githubusercontent.com/litscenes/litscenes/main/scripts/install.sh -o litscenes-install.sh
less litscenes-install.sh
bash litscenes-install.sh
```

The [installer](scripts/install.sh) builds `~/Applications/LitScenes Development.app` without sudo. It preserves existing app bundles, projects and keys, and prints the source revision and retained build directory. Move an existing app aside before reinstalling.

Or build the checkout yourself:

```sh
git clone https://github.com/litscenes/litscenes.git
cd litscenes
swift build
swift test
scripts/build_litscenes_app.sh --channel development
open "dist/LitScenes Development.app"
```

Use the packaged app for media drag-and-drop and file associations. `swift run LitScenes` is also useful for a quick look. Local builds are ad-hoc signed, not notarized release downloads; use macOS's Open action if it asks you to approve the app. No signed DMG is required for the source edition.

## Providers and keys

Open **Settings → API keys**. Start with OpenAI for media analysis and story work; add FAL for its image/video routes or ElevenLabs for voice. **Advanced providers** holds additional keys, compatible text endpoints, and model overrides. The app ships without credentials.

| Provider | Use |
| --- | --- |
| OpenAI or a compatible text endpoint | Analysis, stories and text; OpenAI image generation |
| FAL | Image and video generation |
| Stability | Image generation |
| ElevenLabs | Voice |
| Kling, LTX, Decart | Video generation |
| CivitAI | Image and video recipes |

Generation is optional and billed directly by your selected providers. Local browsing, editing, graph lookup and export require no subscription. OpenAI **Save & Test** checks the supplied credential when you request it. Keys are stored in `credentials.env` with owner-only permissions, or supplied through the process environment.

## Meaning and provenance

The bundled edition contains 1,915 concepts, 1,775 relationships, 3,046 evidence records, 708 aesthetics, 5,958 terms and 10,360 assignments. Its 205 original editorial concepts add care, play, ordinary beauty, shared work, contemporary life and practical film grammar to the literary foundation.

Relationships are interpretive possibilities, not universal rules. Story receives a small selection of concepts and direct relationships as optional inspiration; your brief takes priority. Bibliographic evidence remains separate from creative prompts. The exact provider-bound prompt and workflow outcome remain inspectable in Traces.

[Graph packs and project overlays](docs/meaning-graph.md) explain the YAML format, offline rebuilds, evidence, version pinning and explicit updates. Existing projects retain their graph version and artifacts. Historical managed-job records remain readable; generating again requires an explicit new run with a personal provider key.

## Status and support

LitScenes is beta software. Some editing flows and provider error messages still need refinement. Reproducible reports and ideas are welcome in [GitHub Issues](https://github.com/litscenes/litscenes/issues); see [CONTRIBUTING.md](CONTRIBUTING.md). Individual support and response times are not included.

Development builds keep projects in `~/Library/Application Support/LitScenes/`; Community builds use `~/Library/Application Support/LitScenes Community/`. There is no automatic app updater. Watch [GitHub Releases](https://github.com/litscenes/litscenes/releases) for published versions.

## License and identity

LitScenes Desktop is licensed under `AGPL-3.0-only`; aesthetic metadata retains its `CC-BY-SA-3.0` attribution and terms. The 26 generated starter previews are included under the repository license. Purchased reference composites, raw corpora and private operational history are not included. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

The LitScenes name, logo and official-build identity remain reserved marks; modified distributions should follow [TRADEMARKS.md](TRADEMARKS.md). See [LICENSING.md](LICENSING.md) for the source and commercial licensing terms.

## Export a scene

In **Scenes**, open a scene card’s context menu and choose **Export Scene…**. Choose a destination; the app creates a new portable folder and reveals it in Finder. This is a local presentation export and does not upload or publish your work.

The folder contains one composite image, available ordered frame JPEGs, an optional current-playback MP4 including edits/audio, and `scene.json` / `catalog.json` metadata. Footage placements include a still from their selected start. Missing media is listed as an omission; skipped entries stay marked, and an empty scene can still export. The composite shows up to 16 included frames, with all available frame images saved separately.

The catalog uses the website’s existing collection-v2 envelope, with relative hashed media references and saved ideas marked as project context. It includes no prompts, credentials, inference traces or original local file paths. This is not an editable project backup; website import and reviewed publication are separate workflows.
