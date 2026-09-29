#!/bin/bash
# Build the canonical public source and install a Development-channel app.
# Usage: curl -fsSL https://litscenes.ai/install.sh | bash

main() (
  set -eu
  fail() { printf 'LitScenes: %s\n' "$*" >&2; exit 1; }

  if [ "${1:-}" = '--help' ]; then
    printf '%s\n' 'Build and install LitScenes Development from public source.' \
      'Requires macOS 15+, Swift 6.1+, a macOS 15+ SDK, and internet.' \
      'Installs into ~/Applications. Existing apps and project data are preserved.' \
      'Source and build output remain in ~/Library/Caches/LitScenes.'
    exit 0
  fi
  [ "$#" -eq 0 ] || fail 'Unknown option. Use --help for installation requirements.'
  [ "$(uname -s)" = Darwin ] || fail 'LitScenes Desktop requires macOS 15 or later.'
  [ "$(id -u)" -ne 0 ] || fail 'Run as your normal user, without sudo.'
  if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    fail 'Your home directory is unavailable.'
  fi
  os_version=$(sw_vers -productVersion)
  [ "${os_version%%.*}" -ge 15 ] || fail 'macOS 15 or later is required.'
  for tool in git xcrun ditto codesign; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool. Install Xcode 16.3+ or compatible Command Line Tools, then retry."
  done
  if ! swift_info=$(xcrun swift --version 2>/dev/null); then
    fail 'Swift is unavailable. Install Xcode 16.3+ or compatible Command Line Tools and finish their setup, then retry.'
  fi
  swift_version=$(printf '%s\n' "$swift_info" | awk '{for (i=1; i<NF; i++) if ($i == "Swift" && $(i+1) == "version") {print $(i+2); exit}}')
  [ -n "$swift_version" ] || fail 'Could not determine the selected Swift version.'
  swift_major=${swift_version%%.*}
  swift_minor=$(printf '%s' "$swift_version" | cut -d . -f 2)
  if [ "$swift_major" -lt 6 ] || { [ "$swift_major" -eq 6 ] && [ "$swift_minor" -lt 1 ]; }; then
    fail 'Swift 6.1 or later is required. Update Xcode or Command Line Tools and select that toolchain.'
  fi
  if ! sdk_version=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null); then
    fail 'The macOS SDK is unavailable. Finish Xcode or Command Line Tools setup and retry.'
  fi
  [ "${sdk_version%%.*}" -ge 15 ] || fail 'A macOS 15 or later SDK is required. Update your developer tools.'

  swift_bin=$(xcrun --find swift)
  PATH="$(dirname "$swift_bin"):$PATH"
  export PATH

  applications="$HOME/Applications"
  target="$applications/LitScenes Development.app"
  cache="$HOME/Library/Caches/LitScenes"
  mkdir -p "$applications" "$cache"
  lock="$applications/.litscenes-install.lock"
  mkdir "$lock" 2>/dev/null || fail "An installation may already be running. If it stopped, remove the empty lock folder: $lock"
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT
  if [ -e "$target" ] || [ -L "$target" ]; then
    fail "An app already exists at $target. Quit it and move it aside before reinstalling. Your projects will be kept."
  fi

  workdir=$(mktemp -d "$cache/install.XXXXXX")
  printf 'Building LitScenes from public source. This can take several minutes.\nSource and build output: %s\n' "$workdir"
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main --single-branch \
    https://github.com/litscenes/litscenes.git "$workdir/source"
  cd "$workdir/source"
  printf 'Source revision: %s\n' "$(git rev-parse HEAD)"
  /bin/bash scripts/build_litscenes_app.sh --channel development
  built="$workdir/source/dist/LitScenes Development.app"
  [ -x "$built/Contents/MacOS/LitScenes" ] || fail 'The build did not produce a runnable app.'
  codesign --verify --deep --strict "$built"

  stage=$(mktemp -d "$applications/.litscenes-install.XXXXXX")
  printf 'Staging app: %s\n' "$stage"
  ditto "$built" "$stage/LitScenes Development.app"
  codesign --verify --deep --strict "$stage/LitScenes Development.app"
  if [ -e "$target" ] || [ -L "$target" ]; then
    fail "An app appeared at $target during installation. Staged build kept at $stage."
  fi
  mv "$stage/LitScenes Development.app" "$target"
  rmdir "$stage"
  printf '\nInstalled: %s\nLaunch with: open %q\n' "$target" "$target"
  printf '%s\n' 'This is a local Development build, not a notarized Community release.' \
    'Projects use ~/Library/Application Support/LitScenes, including any existing Development workspace.' \
    'Configure your own provider keys in the app.'
)

# Keep execution last so a partial piped download cannot begin installation.
main "$@"
