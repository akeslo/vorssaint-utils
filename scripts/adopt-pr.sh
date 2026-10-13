#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Carry someone else's open upstream PR on this fork: land its commits (authors kept) on main
# through a fork PR, and list it in scripts/adopted-prs.txt so sync drops it once upstream merges it.
# Usage: scripts/adopt-pr.sh <upstream-pr-number>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
n=$1
UP=vorssaint/vorssaint-utils
info=$(gh pr view "$n" --repo "$UP" --json title,author,url,state)
[[ $(jq -r .state <<<"$info") == OPEN ]] || { echo "upstream #$n is not open" >&2; exit 1; }
scripts/check-carried-licensing.sh "$n"
git fetch --quiet upstream "+pull/$n/head:refs/pr/$n"
shas=(); while read -r s; do shas+=("$s"); done < <(git log --reverse --no-merges --format=%H "refs/pr/$n" --not upstream/main)
title=$(jq -r .title <<<"$info"); author=$(jq -r .author.login <<<"$info"); url=$(jq -r .url <<<"$info")
body=$(printf 'Carries upstream PR %s by @%s: %s\n\nThe commits keep their original authors. Sync drops them once upstream merges this PR.\n' "$url" "$author" "$title")
scripts/land-pr.sh "adopt/$n" "carry upstream #$n: $title" "$body" "${shas[@]}"
git fetch --quiet origin main && git rebase --quiet origin/main
grep -qx "$n" scripts/adopted-prs.txt || echo "$n" >> scripts/adopted-prs.txt
git add scripts/adopted-prs.txt && git commit -q -m "chore(sync): carry upstream PR $n"
echo "adopted #$n; push main with: git push origin main"
