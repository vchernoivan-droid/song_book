#!/usr/bin/env bash

set -eo pipefail

flutter build apk

line=`grep version: pubspec.yaml`
ver="${line#version: }"
ver="${ver/+/-}"

rsync build/app/outputs/apk/release/app-release.apk root@chernoivan.ru:/var/www/chernoivan.ru/song_book/apk/song_book-$ver.apk 

