#!/usr/bin/env bash
# Render App Store teasers from the real Number Reef gameplay.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMO="$ROOT/promo"
EXPORTS="$PROMO/exports"
PREVIEWS="$PROMO/previews"
BUNDLE_ID="Hakketjak.Number-Reef"
SCHEME="Number Reef"
PROJECT="$ROOT/Number Reef.xcodeproj"

mkdir -p "$EXPORTS" "$PREVIEWS"

pick_device() {
  local size="$1"
  local line id
  if [[ "$size" == "1200x1600" ]]; then
    line="$(xcrun simctl list devices available | grep -E 'iPad \(A16\)' | grep -E 'Booted|Shutdown' | head -1)"
  else
    # Prefer a stock iPhone — custom trailer devices can capture black frames.
    line="$(xcrun simctl list devices available | grep -E 'iPhone 17 \(' | grep -E 'Booted|Shutdown' | head -1)"
    if [[ -z "${line}" ]]; then
      line="$(xcrun simctl list devices available | grep -E 'iPhone 16 \(' | grep -E 'Booted|Shutdown' | head -1)"
    fi
    if [[ -z "${line}" ]]; then
      line="$(xcrun simctl list devices available | grep 'Jumping Fox Trailer SE' | grep -E 'Booted|Shutdown' | head -1)"
    fi
  fi
  id="$(printf '%s\n' "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
  printf '%s\n' "$id"
}

render_one() {
  local size="$1"
  local udid
  udid="$(pick_device "$size")"
  if [[ -z "${udid:-}" ]]; then
    echo "No simulator found for $size" >&2
    exit 1
  fi
  echo "==> Rendering $size on $udid"

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b

  local derived="$PROMO/.derived-$size"
  rm -rf "$derived"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    build

  local app
  app="$(find "$derived" -name 'Number Reef.app' -type d | head -1)"
  if [[ -z "$app" ]]; then
    echo "Build product missing" >&2
    exit 1
  fi

  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"

  # Clear previous marker.
  xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data >/tmp/nr-trailer-container-$size.txt 2>/dev/null || true
  local data_container
  data_container="$(cat /tmp/nr-trailer-container-$size.txt 2>/dev/null || true)"

  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" \
    -PromoTrailer \
    "-PromoSize=$size" \
    >"$PROMO/.launch-$size.log" 2>&1 &
  local launch_pid=$!

  echo "Waiting for trailer export..."
  local ready=""
  # Offline encode is slower than realtime on Simulator (~3–8 fps capture).
  # 28s @ 30fps ≈ 840 frames → allow up to ~7 minutes after launch.
  for _ in $(seq 1 420); do
    data_container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [[ -n "$data_container" && -f "$data_container/Documents/promo-trailer-ready.txt" ]]; then
      ready="$(tr -d '\r\n' <"$data_container/Documents/promo-trailer-ready.txt")"
      break
    fi
    sleep 1
  done

  kill "$launch_pid" 2>/dev/null || true
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true

  if [[ -z "$ready" || ! -f "$ready" ]]; then
    # Fallback: look in Documents for the mp4 name.
    local mp4
    mp4="$(find "$data_container/Documents" -name "app-store-teaser-$size.mp4" 2>/dev/null | head -1 || true)"
    if [[ -z "$mp4" ]]; then
      echo "Trailer export failed for $size. Log:" >&2
      tail -80 "$PROMO/.launch-$size.log" >&2 || true
      exit 1
    fi
    ready="$mp4"
  fi

  cp -f "$ready" "$EXPORTS/app-store-teaser-$size.mp4"
  echo "Wrote $EXPORTS/app-store-teaser-$size.mp4"

  # Contact sheet / preview frames via avconvert + sips if available.
  if command -v avconvert >/dev/null 2>&1; then
    :
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$EXPORTS/app-store-teaser-$size.mp4" -vf "fps=1/2,scale=240:-1" "$PREVIEWS/frame-$size-%02d.png" >/dev/null 2>&1 || true
  else
    # Extract a few frames with simctl + python as a light fallback later.
    echo "ffmpeg not installed; skipping contact sheet for $size"
  fi
}

SIZE_FILTER="${1:-all}"
case "$SIZE_FILTER" in
  iphone|886|886x1920) render_one "886x1920" ;;
  ipad|1200|1200x1600) render_one "1200x1600" ;;
  all)
    render_one "886x1920"
    render_one "1200x1600"
    ;;
  *)
    echo "Usage: $0 [all|iphone|ipad]" >&2
    exit 1
    ;;
esac

echo "Done. Exports in $EXPORTS"
