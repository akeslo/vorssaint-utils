#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Land commits on this fork's main through a real PR on the fork, so GitHub records who
# wrote them and where they came from. The PR is rebase-merged: authors and subjects are
# kept (scripts/prune-merged-prs.sh matches on subject) and main stays linear. The merged
# PR record survives the later rebases of main onto upstream.
# Usage: scripts/land-pr.sh <branch> <title> <body> <sha>...   (shas oldest first)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
branch=$1 title=$2 body=$3; shift 3
REMOTE=${LAND_REMOTE:-origin}
ME=$(git remote get-url "$REMOTE" | sed -E 's#^.*github.com[:/]##; s#\.git$##')
# Not `gh pr create` / `gh repo view`: from a fork clone gh resolves to the upstream repo.

git fetch --quiet "$REMOTE" main
tmp=$(mktemp -d)
git worktree add -q --detach "$tmp" "$REMOTE/main"
trap 'git worktree remove --force "$tmp" 2>/dev/null || true' EXIT
git -C "$tmp" -c core.hooksPath=/dev/null cherry-pick "$@" >/dev/null || {
  echo "cherry-pick onto $REMOTE/main conflicts; resolve it by hand in $tmp, then push $branch and open the PR" >&2
  trap - EXIT; exit 1; }
git -C "$tmp" push --quiet --force "$REMOTE" "HEAD:refs/heads/$branch"

url=$(gh api -X POST "repos/$ME/pulls" -f title="$title" -f body="$body" -f head="$branch" -f base=main --jq .html_url)
num=${url##*/}
echo "opened $url"
for _ in 1 2 3 4 5; do   # GitHub computes mergeability asynchronously
  gh api -X PUT "repos/$ME/pulls/$num/merge" -f merge_method=rebase --jq .message 2>/dev/null && break || sleep 4
done
state=$(gh api "repos/$ME/pulls/$num" --jq .merged)
[[ $state == true ]] || { echo "PR $num did not merge" >&2; exit 1; }
git push --quiet "$REMOTE" ":refs/heads/$branch" || true
echo "merged #$num"
