#!/usr/bin/env bash

set -eo pipefail

cd "$(dirname "$0")/.."

. tools/version.sh

flutter build apk --build-name="$VERSION_NAME" --build-number="$VERSION_NUMBER"

rsync -v build/app/outputs/apk/release/app-release.apk \
  "root@chernoivan.ru:/var/www/chernoivan.ru/song_book/apk/song_book-$VERSION_NAME+$VERSION_NUMBER.apk"


