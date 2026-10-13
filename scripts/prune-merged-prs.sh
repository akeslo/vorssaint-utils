#!/usr/bin/env bash
# Find fork features whose upstream PR has been merged, so they can be dropped.
# Rows in scripts/fork-features.tsv: <feature id> <PR number> <subject regex of the feature's commits>.
#   --list   print "<pr> <regex>" for each merged PR (used by sync-upstream.sh to drop commits)
#   --apply  remove the merged features' README blocks and tsv rows
# Test hook: PR_STATE_<number>=MERGED overrides the GitHub lookup.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODE=${1:---list}
TSV=scripts/fork-features.tsv
merged_ids=()

while IFS=$'\t' read -r id pr regex; do
  [[ -n "$id" ]] || continue
  var="PR_STATE_$pr"
  state=${!var:-$(gh pr view "$pr" --repo vorssaint/vorssaint-utils --json state --jq .state)}
  [[ "$state" == MERGED ]] || continue
  merged_ids+=("$id")
  [[ "$MODE" == --list ]] && printf '%s\t%s\n' "$pr" "$regex"
done < "$TSV"

if [[ "$MODE" == --apply && ${#merged_ids[@]} -gt 0 ]]; then
  IDS="${merged_ids[*]}" python3 -I - <<'PY'
import os, re
ids = os.environ["IDS"].split()
s = open("README.md", encoding="utf-8").read()
for i in ids:
    s = re.sub(rf"<!-- feature:{re.escape(i)} -->.*?<!-- /feature:{re.escape(i)} -->\n*", "", s, flags=re.S)
open("README.md", "w", encoding="utf-8").write(s)
rows = [l for l in open("scripts/fork-features.tsv") if l.split("\t")[0] not in ids]
open("scripts/fork-features.tsv", "w").writelines(rows)
PY
  printf 'dropped: %s\n' "${merged_ids[*]}"
fi
