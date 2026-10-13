#!/usr/bin/env bash
# Keep the fork in step with my pull requests on upstream, discovered from GitHub
# (no list to maintain).
#   --list   print "<pr>\t<full sha>" for each fork commit that belongs to a merged PR
#            (matched by commit subject against the PR's own commits)
#   --apply  rewrite the README's open-PR list and drop the README blocks of merged PRs
# README blocks to remove on merge are wrapped in <!-- pr:N --> ... <!-- /pr:N -->.
# Other people's PRs I carry on custom are listed in scripts/adopted-prs.txt (one number per
# line); they are dropped on merge like mine and credited in the README's adopted-prs block.
# Test hook: PRS_JSON overrides the GitHub lookup (gh pr list --json number,title,state,url).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODE=${1:---list}
UP=vorssaint/vorssaint-utils

if [[ -n "${PRS_JSON:-}" ]]; then
  prs=$PRS_JSON
else
  mine=$(gh pr list --repo "$UP" --author akeslo --state all --limit 100 --json number,title,state,url,author)
  adopted=$(for n in $(grep -E '^[0-9]+$' scripts/adopted-prs.txt 2>/dev/null); do
    gh pr view "$n" --repo "$UP" --json number,title,state,url,author
  done | jq -s '.')
  prs=$(jq -sc 'add|unique_by(.number)' <<<"$mine $adopted")
fi

if [[ "$MODE" == --list ]]; then
  git log --no-merges --format='%H%x09%s' upstream/main..HEAD > /tmp/own-commits.$$
  for pr in $(jq -r '.[]|select(.state=="MERGED")|.number' <<<"$prs"); do
    git fetch -q upstream "pull/$pr/head:refs/pr/$pr" 2>/dev/null || continue
    git log --no-merges --format=%s "refs/pr/$pr" --not upstream/main > /tmp/pr-subjects.$$ || true
    # Own commits whose subject the PR also carries.
    awk -F'\t' -v pr="$pr" 'NR==FNR{s[$0]=1;next} ($2 in s){print pr "\t" $1}' /tmp/pr-subjects.$$ /tmp/own-commits.$$
  done
  rm -f /tmp/own-commits.$$ /tmp/pr-subjects.$$
fi

if [[ "$MODE" == --apply ]]; then
  PRS="$prs" python3 -I - <<'PY'
import json, os, re
prs = json.loads(os.environ["PRS"])
s = open("README.md", encoding="utf-8").read()
for n in [p["number"] for p in prs if p["state"] == "MERGED"]:
    s = re.sub(rf"<!-- pr:{n} -->.*?<!-- /pr:{n} -->\n*", "", s, flags=re.S)
adopted = {int(l) for l in open("scripts/adopted-prs.txt").read().split() if l.isdigit()}
open_prs = [p for p in prs if p["state"] == "OPEN" and p["number"] not in adopted]
lines = [f'- [#{p["number"]}]({p["url"]}) {p["title"]}' for p in open_prs] or ["- None right now."]
block = "<!-- upstream-prs -->\nOpen pull requests I have offered upstream:\n\n" + "\n".join(lines) + "\n<!-- /upstream-prs -->"
s = re.sub(r"<!-- upstream-prs -->.*?<!-- /upstream-prs -->", lambda m: block, s, flags=re.S)
carried = [p for p in prs if p["number"] in adopted and p["state"] != "MERGED"]
alines = [f'- [#{p["number"]}]({p["url"]}) {p["title"]}, by [@{p["author"]["login"]}](https://github.com/{p["author"]["login"]})' + (" (closed upstream)" if p["state"] == "CLOSED" else "") for p in carried] or ["- None right now."]
ablock = "<!-- adopted-prs -->\nOther people's upstream pull requests I carry here until they merge:\n\n" + "\n".join(alines) + "\n<!-- /adopted-prs -->"
s = re.sub(r"<!-- adopted-prs -->.*?<!-- /adopted-prs -->", lambda m: ablock, s, flags=re.S)
merged_adopted = {p["number"] for p in prs if p["number"] in adopted and p["state"] == "MERGED"}
if merged_adopted:
    kept = [l for l in open("scripts/adopted-prs.txt").read().split() if not (l.isdigit() and int(l) in merged_adopted)]
    open("scripts/adopted-prs.txt", "w").write("".join(l + "\n" for l in kept))
open("README.md", "w", encoding="utf-8").write(s)
PY
fi
