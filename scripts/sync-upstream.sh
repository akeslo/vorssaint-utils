#!/usr/bin/env bash
# Keep `custom` = latest upstream/main + my own commits on top.
# Rebases custom onto upstream/main (commits upstream already has are dropped
# by patch-id), runs the test harness, then force-pushes with a lease.
# Fork features whose upstream PR has merged are dropped first (scripts/prune-merged-prs.sh).
# Usage: scripts/sync-upstream.sh [--install] [--no-push] [--no-test]
set -euo pipefail

BRANCH=custom
INSTALL=0 PUSH=1 TEST=1
for a in "$@"; do
  case $a in
    --install) INSTALL=1 ;;
    --no-push) PUSH=0 ;;
    --no-test) TEST=0 ;;
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
merged=$(scripts/prune-merged-prs.sh --list)
if [[ -n "$merged" ]]; then
  echo "== upstream merged: PR $(cut -f1 <<<"$merged" | sort -u | paste -sd' ' -); dropping their commits"
  drop=$(cut -f2 <<<"$merged" | sort -u | paste -sd'|' -)
  export GIT_SEQUENCE_EDITOR="sed -E -i.bak '/^pick [0-9a-f]+ [a-z]+(${drop//\//\\/})/s/^pick/drop/'"
  rebase=(git rebase -i upstream/main)
else
  rebase=(git rebase upstream/main)
fi
"${rebase[@]}" || while :; do
  if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "resolve the conflicts, git add, git rebase --continue, then rerun" >&2
    exit 1
  fi
  # rerere resolved everything; keep going
  GIT_EDITOR=true git rebase --continue && break
done
unset GIT_SEQUENCE_EDITOR

if [[ -n "$merged" ]]; then
  scripts/prune-merged-prs.sh --apply
  git commit --quiet -m "docs(readme): drop features that merged upstream" README.md scripts/fork-features.tsv
fi

echo "== my commits on top of upstream/main"
git log --oneline upstream/main.."$BRANCH"

scripts/stamp-upstream-sync.sh
if ! git diff --quiet README.md; then
  git commit --quiet -m "docs(readme): record the latest upstream sync" README.md
fi

if (( TEST )); then timeout 600 ./build.sh --test; fi

if (( PUSH )); then
  git push --force-with-lease origin "$BRANCH"
fi
if (( INSTALL )); then
  ./build.sh --install
fi
echo "== $BRANCH is upstream/main + $(git rev-list --count upstream/main.."$BRANCH") commit(s)"
