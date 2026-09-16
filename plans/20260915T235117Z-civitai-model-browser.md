# Civitai model browser

Implement the owner-approved native browser in existing image and video generation workflows, gated on the personal Civitai key. Include mature previews by default and remember last confirmed image/video recipes across projects.

## Experience
Shared searchable thumbnail grid and detail pane with creator/tag/type/family/sort/favorites filters, pagination, exact versions, compatible LoRAs and weights, trigger-word insertion, and links to Civitai. Default to supported generation choices; unsupported catalog entries stay inspectable with reasons. Browser changes remain draft-only until accepted; render confirmation saves defaults.

## Routes
SD1.5/SDXL checkpoints and LoRAs with text/variant inputs; Flux.2 Klein variants and LoRAs with text/edit inputs; existing WAN 2.7 images; WAN 2.2 Comfy model/LoRA video; WAN 2.5 and 2.7 animation with honest ending capability. Integrate image stack/per-take controls, Shot/Scene model and continuation controls, media Start Video and existing WAN motion/chain controls.

## Contracts
Use authenticated Site catalog/version/mini APIs and orchestration service/resource metadata. Compile explicit family payloads against current OpenAPI. Obtain no-charge whatif quotes before paid rendering. Civitai always uses personal credentials and provider currencies. Freeze versioned recipe snapshots on requests/jobs/artifacts, preserve legacy decode, never silently substitute missing catalog recipes. Safe canonical lifecycle tracing, durable job IDs, recovery without blind resubmission, no credentials or media capabilities in logs.

## Verification and delivery
Exercise catalog/UI/defaults/legacy decode and each family's offline request/quote/recovery paths. Run existing Swift tests, build, hygiene and diff checks, plus REUSE if installed. No paid calls, commits, publication, remote schema changes or submodule advancement without separate consent. Shared implementation belongs to this public repository; private operational details stay private.
