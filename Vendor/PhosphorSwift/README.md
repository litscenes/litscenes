# PhosphorSwift Vendor Subset

This is a minimal local subset of `phosphor-icons/swift` sourced from upstream release `2.1.0`.

The upstream SwiftPM manifest does not declare the asset catalog as a target resource, while the package source requires `Bundle.module`, so the package fails under CLI `swift build`. This local package keeps the public API shape used by LitScenes and declares only the selected icon image sets required by `LitIcon`.
