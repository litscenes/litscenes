# Desktop source installer

The owner selected a paste-in source installer rather than preparing a signed binary release.

1. Maintain the installer in `scripts/install.sh` and publish its command in the README’s Install section.
2. Verify macOS 15+, Swift 6.1+, and a macOS 15+ SDK from Xcode or compatible Command Line Tools before cloning public main.
3. Build with the existing Development packager, report the source revision, verify the app signature, and stage into the user’s Applications folder without sudo. Preserve existing apps and all project/credential data; report retained build output and leave app launch to the user.
4. Validate shell syntax/lint, source hygiene, and the existing build/test suite. Publish the canonical script before the website bootstrap. Commits and publication require separate owner authorization.
