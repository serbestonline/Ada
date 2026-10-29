#!/bin/zsh
# README görsellerini uygulamanın kendisinden üretir: ada sahte bir masaüstünde kare kare çizilir,
# ekran kaydı izni gerekmez. ffmpeg gerekir.
#   ./scripts/make_media.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
APP=build/Ada.app/Contents/MacOS/Ada
WORK=$(mktemp -d)
mkdir -p assets

gif() { # sahne, genişlik
    "$APP" record "$1" "$WORK/$1"
    ffmpeg -y -loglevel error -framerate 12 -i "$WORK/$1/f%05d.png" \
        -vf "scale=$2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "assets/$1.gif"
}
gif work 900; gif done 900; gif hover 900

"$APP" record displays "$WORK/displays"
cp "$WORK/displays/displays.png" assets/
sips -z 512 512 build/AppIcon-1024.png --out assets/icon.png >/dev/null

rm -rf "$WORK"
echo "Görseller assets/ altında yenilendi."
