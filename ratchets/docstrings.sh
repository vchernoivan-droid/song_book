#!/usr/bin/env bash
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
ratchet_file="$repo/ratchets/docstrings"

count=0
while IFS= read -r -d '' f; do
  v=$(awk '
    BEGIN { h = 0; total = 0; inHeader = 1 }
    /^[[:space:]]*\/\/\// { if (inHeader) h++; total++; next }
    /^[[:space:]]*$/ { next }
    {
      if (inHeader) {
        if ($0 ~ /^[[:space:]]*library;[[:space:]]*$/) total -= h
        inHeader = 0
      }
    }
    END { print total }
  ' "$f")
  count=$((count + v))
done < <(find "$repo/lib" -name '*.dart' -print0 2>/dev/null)

baseline=$(cat "$ratchet_file")

if [ "$count" -gt "$baseline" ]; then
  echo "docstring ratchet: $baseline → $count — новые /// разжануй в //" >&2
  exit 1
fi

if [ "$count" -lt "$baseline" ]; then
  printf '%s\n' "$count" > "$ratchet_file"
  echo "docstring ratchet: база обновлена $baseline → $count"
fi
