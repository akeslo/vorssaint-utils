#!/usr/bin/env bash
# GIT_SEQUENCE_EDITOR for sync-upstream.sh: turn "pick" into "drop" for every
# commit whose full sha is listed in $DROP_SHAS (todo lines carry abbreviated shas).
todo=$1
out=$(mktemp)
while IFS= read -r line; do
  if [[ $line =~ ^pick\ ([0-9a-f]+)\  ]]; then
    abbr=${BASH_REMATCH[1]}
    for full in $DROP_SHAS; do
      [[ $full == "$abbr"* ]] && { line="drop${line#pick}"; break; }
    done
  fi
  printf '%s\n' "$line"
done < "$todo" > "$out"
mv "$out" "$todo"
