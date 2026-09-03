#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHANNEL="development"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --help)
      echo "usage: $0 [--channel development|community-release|official-commercial-release]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

PUBLIC_REPOSITORY_HTTPS="https://github.com/litscenes/litscenes"
PUBLIC_REPOSITORY_SSH="git@github.com:litscenes/litscenes.git"
SOURCE_REVISION=""
SOURCE_URL=""
UPDATE_FEED_URL=""
SIGNING_IDENTITY="-"
LICENSE_SOURCE=""

case "$CHANNEL" in
  development)
    APP_NAME="LitScenes Development"
    BUNDLE_ID="ai.litscenes.development"
    ICON_SOURCE="$ROOT/design/community/LitScenesCommunityIcon.png"
    SOURCE_REVISION="$(git rev-parse HEAD 2>/dev/null || true)"
    ;;
  community-release)
    APP_NAME="LitScenes Community"
    BUNDLE_ID="ai.litscenes.community"
    ICON_SOURCE="$ROOT/design/community/LitScenesCommunityIcon.png"
    LICENSE_SOURCE="$ROOT/LICENSE"
    SIGNING_IDENTITY="${LITSCENES_COMMUNITY_SIGNING_IDENTITY:-}"

    if [[ ! -d "$ROOT/.git" ]]; then
      echo "Community release refused: build from a clean clone of $PUBLIC_REPOSITORY_HTTPS." >&2
      exit 65
    fi
    ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
    if [[ "$ORIGIN_URL" != "$PUBLIC_REPOSITORY_HTTPS" && "$ORIGIN_URL" != "$PUBLIC_REPOSITORY_HTTPS.git" && "$ORIGIN_URL" != "$PUBLIC_REPOSITORY_SSH" ]]; then
      echo "Community release refused: origin is not $PUBLIC_REPOSITORY_HTTPS." >&2
      exit 65
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Community release refused: the public checkout is not clean." >&2
      exit 65
    fi
    if [[ ! -f "$LICENSE_SOURCE" ]]; then
      echo "Community release refused: root LICENSE is missing." >&2
      exit 65
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
      echo "Community release refused: LITSCENES_COMMUNITY_SIGNING_IDENTITY is required." >&2
      exit 65
    fi
    SOURCE_REVISION="$(git rev-parse HEAD)"
    REMOTE_REFS="$(git ls-remote origin)"
    if ! grep -q "^${SOURCE_REVISION}[[:space:]]" <<<"$REMOTE_REFS"; then
      echo "Community release refused: $SOURCE_REVISION is not reachable from public origin." >&2
      exit 65
    fi
    SOURCE_URL="$PUBLIC_REPOSITORY_HTTPS/tree/$SOURCE_REVISION"
    ;;
  official-commercial-release)
    APP_NAME="LitScenes"
    BUNDLE_ID="${LITSCENES_OFFICIAL_BUNDLE_ID:-}"
    ICON_SOURCE="${LITSCENES_OFFICIAL_ICON_PATH:-}"
    LICENSE_SOURCE="${LITSCENES_OFFICIAL_EULA_PATH:-}"
    SIGNING_IDENTITY="${LITSCENES_OFFICIAL_SIGNING_IDENTITY:-}"
    UPDATE_FEED_URL="${LITSCENES_OFFICIAL_UPDATE_FEED_URL:-}"

    for REQUIRED_NAME in BUNDLE_ID ICON_SOURCE LICENSE_SOURCE SIGNING_IDENTITY UPDATE_FEED_URL; do
      if [[ -z "${!REQUIRED_NAME}" ]]; then
        echo "Official commercial release refused: $REQUIRED_NAME is missing from the rights-holder release configuration." >&2
        exit 65
      fi
    done
    SOURCE_REVISION="$(git rev-parse HEAD 2>/dev/null || true)"
    ;;
  *)
    echo "Unknown release channel: $CHANNEL" >&2
    exit 64
    ;;
esac

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing release icon: $ICON_SOURCE" >&2
  exit 66
fi
if [[ -n "$LICENSE_SOURCE" && ! -f "$LICENSE_SOURCE" ]]; then
  echo "Missing release license/EULA: $LICENSE_SOURCE" >&2
  exit 66
fi

swift build --product LitScenes
BIN_DIR="$(swift build --show-bin-path)"
APP_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/LitScenes"
RESOURCE_BUNDLE="$BIN_DIR/LitScenes_LitScenes.bundle"

if [[ -e "$APP_DIR" ]]; then
  DEPRECATED_DIR="$ROOT/dist/.deprecated_${APP_NAME// /_}.app_$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$APP_DIR" "$DEPRECATED_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/LitScenes" "$EXECUTABLE"
chmod +x "$EXECUTABLE"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/LitScenes_LitScenes.bundle"

ICONSET_DIR="$ROOT/dist/${APP_NAME// /_}.iconset"
if [[ -e "$ICONSET_DIR" ]]; then
  DEPRECATED_ICONSET="$ROOT/dist/.deprecated_${APP_NAME// /_}.iconset_$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$ICONSET_DIR" "$DEPRECATED_ICONSET"
fi
mkdir -p "$ICONSET_DIR"

generate_icon_png() {
  local pixel_size="$1"
  local filename="$2"
  sips -s format png -z "$pixel_size" "$pixel_size" "$ICON_SOURCE" --out "$ICONSET_DIR/$filename" >/dev/null
}

generate_icon_png 16 "icon_16x16.png"
generate_icon_png 32 "icon_16x16@2x.png"
generate_icon_png 32 "icon_32x32.png"
generate_icon_png 64 "icon_32x32@2x.png"
generate_icon_png 128 "icon_128x128.png"
generate_icon_png 256 "icon_128x128@2x.png"
generate_icon_png 256 "icon_256x256.png"
generate_icon_png 512 "icon_256x256@2x.png"
generate_icon_png 512 "icon_512x512.png"
generate_icon_png 1024 "icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

if [[ -n "$LICENSE_SOURCE" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/Legal"
  if [[ "$CHANNEL" == "community-release" ]]; then
    for LEGAL_FILE in LICENSE LICENSING.md TRADEMARKS.md NOTICE THIRD_PARTY_LICENSES.md; do
      if [[ ! -f "$ROOT/$LEGAL_FILE" ]]; then
        echo "Community release refused: $LEGAL_FILE is missing." >&2
        exit 66
      fi
      cp "$ROOT/$LEGAL_FILE" "$APP_DIR/Contents/Resources/Legal/$LEGAL_FILE"
    done
    # Upstream license texts (MIT, AGPL, ...) ship with the binary too — the
    # inventory table alone does not satisfy attribution requirements.
    if [[ ! -d "$ROOT/LICENSES" ]]; then
      echo "Community release refused: LICENSES/ directory is missing." >&2
      exit 66
    fi
    mkdir -p "$APP_DIR/Contents/Resources/Legal/LICENSES"
    cp "$ROOT/LICENSES/"*.txt "$APP_DIR/Contents/Resources/Legal/LICENSES/"
  else
    cp "$LICENSE_SOURCE" "$APP_DIR/Contents/Resources/Legal/COMMERCIAL-EULA.txt"
  fi
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>LitScenes</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LitScenesReleaseChannel</key>
  <string>$CHANNEL</string>
  <key>LitScenesCorrespondingSourceURL</key>
  <string>$SOURCE_URL</string>
  <key>LitScenesSourceRevision</key>
  <string>$SOURCE_REVISION</string>
  <key>LitScenesUpdateFeedURL</key>
  <string>$UPDATE_FEED_URL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>$APP_NAME uses the camera when you record camera media or add your face to a session recording.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>$APP_NAME uses the microphone when you record camera media, a voiceover take for a shot, or a session recording's narration.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>$APP_NAME saves finished session recordings from File &gt; Record Session to your Downloads folder.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.litscenes.cut</string>
      <key>UTTypeDescription</key>
      <string>LitScenes Shot drag payload</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.litscenes.scene.v2</string>
      <key>UTTypeDescription</key>
      <string>LitScenes Scene rail drag payload</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.litscenes.sequence.coin</string>
      <key>UTTypeDescription</key>
      <string>LitScenes Output-sequence reorder payload</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.litscenes.shot-picture-segment</string>
      <key>UTTypeDescription</key>
      <string>LitScenes Shot picture-segment clipboard payload</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.litscenes.shot-audio-region</string>
      <key>UTTypeDescription</key>
      <string>LitScenes Shot audio-region clipboard payload</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_DIR" >/dev/null

# Re-register the bundle with Launch Services: the UTExportedTypeDeclarations
# power in-app drag & drop (drop targets never match an unregistered custom
# UTType), and a replaced bundle at the same path can otherwise serve a stale
# registration until the next launch.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" || true
fi

echo "$APP_DIR"
