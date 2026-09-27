#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cache_dir="/tmp/number-reef-swift-cache"
master="$root/promo/master-video.swift"
duration="21.2"

mkdir -p "$root/promo/exports"
cd "$root"
xcrun swift -module-cache-path "$cache_dir" -framework AVFoundation "$master" \
  promo/captures/premium-iphone-raw.mp4 \
  promo/exports/number-reef-app-store-premium-tour-886x1920.mp4 \
  886 1920 2.00 "$duration" promo/captures/premium-iphone-events.tsv 0

sleep 5

xcrun swift -module-cache-path "$cache_dir" -framework AVFoundation "$master" \
  promo/captures/premium-ipad-raw.mp4 \
  promo/exports/number-reef-app-store-premium-tour-1200x1600.mp4 \
  1200 1600 2.00 "$duration" promo/captures/premium-ipad-events.tsv 0
