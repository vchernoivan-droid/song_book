#!/usr/bin/env bash
set -euo pipefail

svg=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
size=$2
out=$3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# без width/height Chrome рисует standalone-SVG в его собственные 1024 и отдаёт кроп окна
sed "s|<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=|<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$size\" height=\"$size\" viewBox=|" \
  "$svg" > "$work/icon.svg"

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --default-background-color=00000000 --window-size="$size,$size" \
  --screenshot="$out" "file://$work/icon.svg" 2>/dev/null

width=$(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}')
if [ "$width" != "$size" ]; then
  echo "render: $out получился $width вместо $size" >&2
  exit 1
fi
