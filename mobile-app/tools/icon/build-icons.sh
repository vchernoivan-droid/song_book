#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$here/.work

rm -rf "$work"
mkdir -p "$work"

# те же линии, но ужатые в безопасную зону маски: adaptive-фон и maskable-web режут края плитки
sed -e 's|<rect id="bg"[^>]*/>||' -e 's|scale(1)|scale(0.76)|' "$here/icon.svg" > "$work/foreground.svg"
sed -e 's|scale(1)|scale(0.76)|' "$here/icon.svg" > "$work/maskable.svg"

bleed() { "$here/render.sh" "$here/icon.svg" "$1" "$2"; }
safe() { "$here/render.sh" "$work/$1.svg" "$2" "$3"; }

android=$root/android/app/src/main/res
ios=$root/ios/Runner/Assets.xcassets/AppIcon.appiconset
macos=$root/macos/Runner/Assets.xcassets/AppIcon.appiconset

mkdir -p "$android/mipmap-anydpi-v26"

bleed 48 "$android/mipmap-mdpi/ic_launcher.png"
bleed 72 "$android/mipmap-hdpi/ic_launcher.png"
bleed 96 "$android/mipmap-xhdpi/ic_launcher.png"
bleed 144 "$android/mipmap-xxhdpi/ic_launcher.png"
bleed 192 "$android/mipmap-xxxhdpi/ic_launcher.png"

safe foreground 108 "$android/mipmap-mdpi/ic_launcher_foreground.png"
safe foreground 162 "$android/mipmap-hdpi/ic_launcher_foreground.png"
safe foreground 216 "$android/mipmap-xhdpi/ic_launcher_foreground.png"
safe foreground 324 "$android/mipmap-xxhdpi/ic_launcher_foreground.png"
safe foreground 432 "$android/mipmap-xxxhdpi/ic_launcher_foreground.png"

cat > "$android/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML

cat > "$android/drawable/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient android:angle="315" android:startColor="#4154BD" android:endColor="#161E5C"/>
</shape>
XML

bleed 20 "$ios/Icon-App-20x20@1x.png"
bleed 40 "$ios/Icon-App-20x20@2x.png"
bleed 60 "$ios/Icon-App-20x20@3x.png"
bleed 29 "$ios/Icon-App-29x29@1x.png"
bleed 58 "$ios/Icon-App-29x29@2x.png"
bleed 87 "$ios/Icon-App-29x29@3x.png"
bleed 40 "$ios/Icon-App-40x40@1x.png"
bleed 80 "$ios/Icon-App-40x40@2x.png"
bleed 120 "$ios/Icon-App-40x40@3x.png"
bleed 120 "$ios/Icon-App-60x60@2x.png"
bleed 180 "$ios/Icon-App-60x60@3x.png"
bleed 76 "$ios/Icon-App-76x76@1x.png"
bleed 152 "$ios/Icon-App-76x76@2x.png"
bleed 167 "$ios/Icon-App-83.5x83.5@2x.png"
bleed 1024 "$ios/Icon-App-1024x1024@1x.png"

bleed 16 "$macos/app_icon_16.png"
bleed 32 "$macos/app_icon_32.png"
bleed 64 "$macos/app_icon_64.png"
bleed 128 "$macos/app_icon_128.png"
bleed 256 "$macos/app_icon_256.png"
bleed 512 "$macos/app_icon_512.png"
bleed 1024 "$macos/app_icon_1024.png"

bleed 192 "$root/web/icons/Icon-192.png"
bleed 512 "$root/web/icons/Icon-512.png"
safe maskable 192 "$root/web/icons/Icon-maskable-192.png"
safe maskable 512 "$root/web/icons/Icon-maskable-512.png"
bleed 32 "$root/web/favicon.png"

ico_sizes=(16 24 32 48 64 128 256)
ico_files=()
for size in "${ico_sizes[@]}"; do
  ico_files+=("$work/ico-$size.png")
  bleed "$size" "$work/ico-$size.png"
done
dart "$here/build_ico.dart" "$root/windows/runner/resources/app_icon.ico" "${ico_files[@]}"

rm -rf "$work"
echo "иконки собраны"
