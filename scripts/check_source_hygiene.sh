#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "check_source_hygiene: rg (ripgrep) is required." >&2
  exit 69
fi

status=0
fail() {
  echo "check_source_hygiene: $1" >&2
  status=70
}

scan() {
  local label="$1"
  shift
  local output=""
  local scan_status=0
  output="$(rg -n "$@" 2>&1)" || scan_status=$?
  if [[ "$scan_status" -ge 2 ]]; then
    echo "$output" >&2
    echo "check_source_hygiene: rg scanner error (exit $scan_status)." >&2
    exit 71
  fi
  if [[ "$scan_status" -eq 0 && -n "$output" ]]; then
    echo "$output" >&2
    fail "$label"
  fi
}

scan "dated engineering comment in shipped source" \
  '(^|[^:])//.*20(25|26)-[0-9]{2}-[0-9]{2}' \
  "$ROOT/Sources" "$ROOT/Tests" --glob '*.swift'

scan "dated block comment in shipped source" \
  '^[[:space:]]*\*+.*20(25|26)-[0-9]{2}-[0-9]{2}' \
  "$ROOT/Sources" "$ROOT/Tests" --glob '*.swift'

scan "private or retired runtime boundary in public source" \
  '(QAHarness|QANetworkGuard|LITSCENES_QA_(PORT|BLOCK_NETWORK|ALLOW_HOSTS)|qa-harness|PostgresNIO|LitScenesGraphReview)' \
  "$ROOT/Sources" "$ROOT/Tests" "$ROOT/Package.swift"

scan "private decision vocabulary in shipped source" \
  '(ratified|owner decision|owner-ratified|smoke test)' \
  "$ROOT/Sources" --glob '*.swift'

sub_day="$(rg -n '20(25|26)-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' \
  "$ROOT/Sources/LitScenes/Resources" --glob '!**/CatalogFallback/**' | grep -v 'T00:00:00' || true)"
if [[ -n "$sub_day" ]]; then
  echo "$sub_day" >&2
  fail "sub-day timestamp in bundled resources"
fi

for forbidden in LitScenesPrivate LitScenesGraphReview QAHarness AestheticIndexImages meaning_choice_index_full.json; do
  hit="$(find "$ROOT" \
    -path "$ROOT/.git" -prune -o \
    -path "$ROOT/.build" -prune -o \
    -name "$forbidden" -print -quit)"
  if [[ -n "$hit" ]]; then
    echo "$hit" >&2
    fail "forbidden private path $forbidden"
  fi
done

scan "secret-shaped content in public working tree" \
  --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!scripts/check_source_hygiene.sh' \
  '(AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|(OPENAI_API_KEY|FAL_API_KEY|FAL_KEY|ELEVEN_LABS_API_KEY|ELEVENLABS_API_KEY|STABILITY_AI_API_KEY|STABILITY_API_KEY|CIVITAI_API_KEY|DECART_API_KEY|KLING_API_KEY|KLING_ACCESS_KEY|KLING_SECRET_KEY|KLINGAI_API_KEY|LTX_API_KEY|LTXV_API_KEY|AUTH_TOKEN)[[:space:]]*=[[:space:]]*[^$<{[:space:]]|https?://[^/@[:space:]]+:[^/@[:space:]]+@|\bsk-[A-Za-z0-9_-]{24,}|eyJ[A-Za-z0-9_-]{20,}\.eyJ)' \
  "$ROOT"

if [[ "$status" -eq 0 ]]; then
  echo "check_source_hygiene: clean."
fi
exit "$status"

