#!/usr/bin/env bash
set -euo pipefail

major=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/[.].*//')
export VERSION_NAME="$major.$(git log -1 --format=%cd --date=format:%Y.%m)"
export VERSION_NUMBER="$(( $(git rev-list --count HEAD) + 100 ))"
