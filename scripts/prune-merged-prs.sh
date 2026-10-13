#!/usr/bin/env bash
# Keep the fork in step with my pull requests on upstream, discovered from GitHub
# (no list to maintain).
#   --list   print "<pr>\t<full sha>" for each fork commit that belongs to a merged PR
#            (matched by commit subject against the PR's own commits)
#   --apply  rewrite the README's open-PR list and drop the README blocks of merged PRs
# README blocks to remove on merge are wrapped in <!-- pr:N --> ... <!-- /pr:N -->.
# Test hook: PRS_JSON overrides the GitHub lookup (gh pr list --json number,title,state,url).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODE=${1:---list}
UP=vorssaint/vorssaint-utils

prs=${PRS_JSON:-$(gh pr list --repo "$UP" --author akeslo --state all --limit 100 --json number,title,state,url)}

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
open_prs = [p for p in prs if p["state"] == "OPEN"]
lines = [f'- [#{p["number"]}]({p["url"]}) {p["title"]}' for p in open_prs] or ["- None right now."]
block = "<!-- upstream-prs -->\nOpen pull requests I have offered upstream:\n\n" + "\n".join(lines) + "\n<!-- /upstream-prs -->"
s = re.sub(r"<!-- upstream-prs -->.*?<!-- /upstream-prs -->", lambda m: block, s, flags=re.S)
open("README.md", "w", encoding="utf-8").write(s)
PY
fi
