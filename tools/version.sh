#!/usr/bin/env bash
# Версия MAJOR.YEAR.MONTH+BUILD: MAJOR из pubspec.yaml, YEAR.MONTH — последний коммит, BUILD — история git.
set -euo pipefail

major=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/[.].*//')
export VERSION_NAME="$major.$(git log -1 --format=%cd --date=format:%Y.%m)"
export VERSION_NUMBER="$(git rev-list --count HEAD)"
