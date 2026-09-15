# LitScenes

An open-source A.I. first desktop app for macOS — for stories longer than a prompt. More info at [litscenes.ai](https://litscenes.ai) . Built with Aloha by [oahu.ai](https://oahu.ai)



https://github.com/user-attachments/assets/0c371be6-f1b8-4f61-ad32-45be4e5ae80b




## A letter from the maker

I built LitScenes because I wanted to make videos that hold together as stories — across scenes, across characters, across whole projects — and nothing I tried worked at that layer. I think this is the best interface yet for multi-project, multi-scene, story-rich video generation. The app builds meaning and structure first; frames and renders follow from them.

It is not finished. There are plenty of gaps — some flows are rough, and the documentation trails the app. That is also the good news: LitScenes is easy and ready to improve, and the code is now yours to improve it with.

I need to make a living, so paid services and products exist alongside this free app: a hosted meaning-graph service today, probably more over time. The app does not depend on any of them. They are there for people who want them, and they are what keeps the free thing free.

If you find LitScenes useful, and it helps you drive a good story into the world, I would be delighted. That is the point.

Kevin Riggen - kevin@oahu.ai

## Features

- **Story spine.** A Goal interview establishes what the story is for, Frame Context grounds it in your material, Scene Stories break it into scenes, and Frame Forms turn each scene into concrete frames. Structure comes before pixels. In the app this runs through the MEDIA, STORY, and SCENES workspaces.
- **Scenes, shots, and cuts.** Compose scenes into shots, edit at the cut layer — trims, skips, seams, loops — and assemble the result locally. The preview is the export.
- **Renders through your own providers.** Bring your own keys. OpenAI drives story and text; optional providers cover image, video, and voice.
- **Local-first projects.** Your projects, media, and renders live on your Mac. Network requests serve configured providers, the Go service when you choose to use it, and the style catalog when you enable or refresh it (see below).
- **No telemetry.** Zero analytics, zero tracking. An unconfigured install makes no background network requests. Opening Account & usage or choosing Go contacts the account service; connected accounts refresh payment and job status. The bundled style catalog serves until you turn on the live catalog or explicitly refresh it from catalog.litscenes.ai. The CI test suite runs under a network-deny sandbox to keep this true.

## Where LitScenes sits

Velorn, OpenScene, and SynthCut are excellent AI-native timeline editors and agent-driven editing layers. LitScenes works at a different layer: story — meaning, structure, character continuity, and long-form coherence across scenes and projects.

## Status

LitScenes is in beta. It works, and it has rough edges:

- First launch offers Go, guided personal-key setup, account recovery, and Explore first. Go availability depends on the account service.
- Documentation trails the app.
- Some editing flows are unpolished.
- Provider errors are sometimes surfaced tersely.

Expect steady improvement, and see `CONTRIBUTING.md` if you want to help.

## Install

**Build from source.** Requires macOS 15 or later and Xcode 16.3+ (Swift 6.1).

```sh
git clone https://github.com/litscenes/litscenes.git
cd litscenes
swift build
swift test
scripts/build_litscenes_app.sh --channel development
open "dist/LitScenes Development.app"
```

`swift run LitScenes` also works for a quick look, but the bare executable
skips the app bundle's file-type declarations, so drag-and-drop of media is
disabled there — prefer the built app. Local builds are unsigned: if
Gatekeeper objects, right-click the app and choose Open the first time.

**Signed Community DMG.** Signed, notarized builds will be published on the
GitHub Releases page; until then, build from source.

## Providers and keys

Personal-key mode starts with one OpenAI key. Go provides managed generation and hosted story context through a paid account when the service is available. The app ships with no provider secrets.

| Provider | Used for | Required |
| --- | --- | --- |
| OpenAI | Story, text, and meaning work | Yes |
| FAL | Image and video generation | Optional |
| Stability | Image generation | Optional |
| ElevenLabs | Voice | Optional |
| Kling | Video generation | Optional |
| LTX | Video generation | Optional |
| CivitAI | Image models and styles | Optional |
| Decart | Video generation | Optional |

Keys live in a `credentials.env` file with `600` permissions, or in the process environment. They never leave your machine except in calls to the provider they belong to.

Personal-key setup offers OpenAI Save & Test. Video and narration request additional provider setup when needed. Account & usage is the default Settings tab; additional provider keys, custom endpoints, and model overrides live in Advanced.

## Story inference

Personal-key mode uses an OpenAI-compatible provider with the bundled starter meaning vocabulary. Advanced settings support compatible endpoint and model overrides.

Go includes hosted story context and managed inference. Users connect a Go account; they do not configure a graph service endpoint or token. Choosing a funding mode affects future work across projects and preserves existing media. Local import, browsing, editing, and export remain available without a subscription.

## Troubleshooting

- **Where things live.** Projects, media indexes, and `credentials.env` sit under `~/Library/Application Support/LitScenes Community/` (a development-channel build uses `…/LitScenes/`).
- **Costs.** Personal-key renders bill your provider accounts. Go shows a server quote and asks for maximum credit approval before generation; a purchase alone does not start a render.
- **Provider errors.** Personal key problems show in setup or Advanced settings; other failures surface on the render's status line.
- **Reset the first-run welcome.** `defaults delete ai.litscenes.community litscenes.welcome.seen_version` (use your channel's suite).
- **Updates.** There is no auto-update; watch the GitHub Releases page.

## Sustainability

Here is the honest economics of this project.

The code is licensed `AGPL-3.0-only`: you can use, modify, sell, and redistribute LitScenes, but derivatives stay open — the AGPL is what stops a proprietary fork. Separately, trademark policy (not the AGPL) reserves the LitScenes name, icon, and official-build identity, so a modified distribution must rename and re-badge; see `TRADEMARKS.md`. A commercial license is available for organizations that need different terms; see `LICENSING.md`.

Optional paid services fund work on the free app. Go bundles hosted story context with a monthly generation allowance; availability and the current offer appear in Account & usage. The free app stays free, and stays complete.

## Contributing

See `CONTRIBUTING.md`. GitHub Issues for reproducible bugs and GitHub Discussions for questions are welcome. LitScenes is provided as a community project: individual support, implementation assistance, and response times are not included. Pull requests are currently limited while the contributor license agreement is finalized.

## License and Trademarks

LitScenes Desktop is licensed under `AGPL-3.0-only`; see `LICENSE` and `LICENSING.md`. A separate commercial license is available. The LitScenes name, logo, icon, and official-build identity are reserved marks; see `TRADEMARKS.md`.

---

Created and maintained by [Kevin Riggen](https://litscenes.ai).
