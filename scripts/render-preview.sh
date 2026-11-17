#!/bin/bash
# Offscreen publication tool; never opens a visible document or reads the user's desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bash scripts/swift-local.sh build --product ClimbChecks >&2
BIN=$(bash scripts/swift-local.sh build --show-bin-path)
swiftc -module-cache-path "$WORK/cache" -I "$BIN/Modules" scripts/promo/*.swift \
    Sources/Sisyphus/{CharacterView,ClimberView,SpiderArt,SpiderRenderer}.swift "$BIN"/ClimbCore.build/*.swift.o -o "$WORK/render"
# Decode the named Apple asset with software HEVC, including tiled HEIC on a headless Mac.
export SISYPHUS_PROMO_WALLPAPER="$WORK/stock.png"
ffmpeg -hide_banner -loglevel error -threads 2 -i '/System/Library/Desktop Pictures/Sonoma.heic' -frames:v 1 "$SISYPHUS_PROMO_WALLPAPER"
if [ "$#" -eq 0 ]; then
    mkdir -p docs/media
    "$WORK/render" "$WORK/frames" 0 16.8 --drop
    ffmpeg -hide_banner -loglevel error -y -framerate 20 -i "$WORK/frames/frame-%04d.png" \
        -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
        -loop 0 docs/media/mac-desktop.gif
else
    "$WORK/render" "$@"
fi
