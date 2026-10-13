#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 akeslo
# Rewrite the "last synced with upstream" block in README.md from the commit
# this branch is currently based on (merge-base with upstream/main).
# Idempotent: only touches README.md when the stamp changed.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

base=$(git merge-base HEAD upstream/main 2>/dev/null) || exit 0
sha=$(git rev-parse --short "$base")
date=$(git log -1 --format=%cs "$base")
subject=$(git log -1 --format=%s "$base")
tag=$(git describe --tags --abbrev=0 "$base" 2>/dev/null || true)
line="Last synced with [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) at [\`$sha\`](https://github.com/vorssaint/vorssaint-utils/commit/$base) on $date (\"$subject\")${tag:+, after release $tag}."

STAMP="$line" python3 -I - <<'PY'
import os, re
p = "README.md"
s = open(p, encoding="utf-8").read()
new = "<!-- upstream-sync -->\n" + os.environ["STAMP"] + "\n<!-- /upstream-sync -->"
out = re.sub(r"<!-- upstream-sync -->.*?<!-- /upstream-sync -->", lambda m: new, s, flags=re.S)
if out != s:
    open(p, "w", encoding="utf-8").write(out)
PY
