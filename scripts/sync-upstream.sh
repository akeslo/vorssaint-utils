#!/usr/bin/env bash
# Keep `custom` = latest upstream/main + my own commits on top.
# Rebases custom onto upstream/main (commits upstream already has are dropped
# by patch-id), runs the test harness, then force-pushes with a lease.
# Usage: scripts/sync-upstream.sh [--install] [--no-push]
set -euo pipefail

BRANCH=custom
INSTALL=0 PUSH=1
for a in "$@"; do
  case $a in
    --install) INSTALL=1 ;;
    --no-push) PUSH=0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "working tree dirty; commit or stash first" >&2; exit 1; }

# Replay conflict resolutions recorded on earlier runs.
git config rerere.enabled true
git config rerere.autoupdate true

git fetch --quiet upstream --tags
git fetch --quiet origin
git switch --quiet "$BRANCH"

echo "== rebasing $BRANCH onto upstream/main ($(git describe --tags upstream/main))"
git rebase upstream/main || while :; do
  if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "resolve the conflicts, git add, git rebase --continue, then rerun" >&2
    exit 1
  fi
  # rerere resolved everything; keep going
  GIT_EDITOR=true git rebase --continue && break
done

echo "== my commits on top of upstream/main"
git log --oneline upstream/main.."$BRANCH"

scripts/stamp-upstream-sync.sh
if ! git diff --quiet README.md; then
  git commit --quiet -m "docs(readme): record the latest upstream sync" README.md
fi

timeout 600 ./build.sh --test

if (( PUSH )); then
  git push --force-with-lease origin "$BRANCH"
fi
if (( INSTALL )); then
  ./build.sh --install
fi
echo "== $BRANCH is upstream/main + $(git rev-list --count upstream/main.."$BRANCH") commit(s)"
