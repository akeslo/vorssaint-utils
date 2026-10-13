#!/usr/bin/env bash
# Licensing gate for carried PRs and GPL duties. Run before adding a number to
# scripts/adopted-prs.txt and before publishing any binary. Exit 1 on a finding.
set -uo pipefail
cd "$(dirname "$0")/.."
bad=0

# GPL duties: LICENSE untouched, TRADEMARKS.md untouched.
for f in LICENSE TRADEMARKS.md; do
  if ! git diff --quiet upstream/main -- "$f"; then echo "FAIL: $f differs from upstream/main"; bad=1; fi
done

# Carried PRs: only upstream's own header, no new foreign licenses, no non-system imports.
prs=${*:-$(grep -E '^[0-9]+$' scripts/adopted-prs.txt)}
for n in $prs; do
  d=$(gh pr diff "$n" --repo vorssaint/vorssaint-utils) || { echo "FAIL: cannot fetch #$n"; bad=1; continue; }
  added=$(grep -E '^\+' <<<"$d" | grep -vE '^\+\+\+')
  if grep -iE 'copyright|SPDX-License' <<<"$added" | grep -vE 'SPDX-License-Identifier: GPL-3.0-or-later|Copyright \(C\) 2026 Vorssaint' | grep -q .; then
    echo "FAIL: #$n adds a license or copyright line other than upstream's"; bad=1; fi
  if grep -iE 'apache|BSD|\bMIT licen|adapted from|based on|ported from|stackoverflow|gist\.github' <<<"$added" | grep -q .; then
    echo "REVIEW: #$n mentions another source or license"; bad=1; fi
  if grep -E '^\+\s*(@_exported )?import ' <<<"$added" | grep -vE 'import (AppKit|Foundation|SwiftUI|Combine|CoreGraphics|CoreImage|IOKit|Vision|ImageIO|UniformTypeIdentifiers|XCTest|OSLog|os)\b' | grep -q .; then
    echo "REVIEW: #$n imports a non-system module"; bad=1; fi
  grep -qE '^\+\+\+ b/(Package\.(swift|resolved)|Vendor|ThirdParty)' <<<"$d" && { echo "FAIL: #$n touches dependencies"; bad=1; }
  echo "checked #$n"
done
exit $bad
