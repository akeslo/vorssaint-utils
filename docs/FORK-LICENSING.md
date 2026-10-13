# Fork licensing rules

Not legal advice. Audited 2026-10-13 against upstream's LICENSE, TRADEMARKS.md, CONTRIBUTING.md and docs/AI-CONTRIBUTIONS.md.

## Carried PRs (`scripts/adopted-prs.txt`)

- Contributors submit under upstream's GPL-3.0-or-later terms, so carrying their commits is allowed.
- Keep each author's name on the cherry-pick and credit them in the README's adopted list (generated). Each carried PR lands on `main` through a merged PR on this fork (`scripts/adopt-pr.sh <n>`, via `scripts/land-pr.sh`), so GitHub keeps who wrote what and the upstream link; sync drops the commits once upstream merges it.
- Before adding a number, run `scripts/check-carried-licensing.sh <pr>`. It fails on any added license or copyright line other than upstream's own header, mentions of another source, non-system imports, or dependency changes. Fix or reject on a finding.
- Checked 2026-10-13, all clean (Apple frameworks only, upstream header only): #1879, #2909, #3010, #2966.

## GPL duties

- Files I author carry only the `SPDX-License-Identifier: GPL-3.0-or-later` line, with no copyright-holder line: that is left to upstream's maintainer if a file is PRed over. Never remove or edit another author's or upstream's header.
- Keep `LICENSE` and every upstream file's copyright header intact; `scripts/check-carried-licensing.sh` fails if `LICENSE` or `TRADEMARKS.md` differ from upstream.
- Publishing a binary requires offering the source. The public repo covers that. Before any binary leaves this machine, also replace the Vorssaint name, bundle ID, icon and update feed (TRADEMARKS.md).

## Artwork

- The app icon, in-app mark and README logo are this fork's own Moonlit artwork (GPL-3.0-or-later), drawn by `Tools/MakeMoonlitArt.swift` and `docs/assets/readme/moonlit.svg`. Upstream's non-GPL logo files were removed from the tree; they remain in git history, which a fork shares with upstream.
- Never copy upstream's `Resources/Brand` or `docs/assets/readme/logo*` files back in. If a sync conflicts on those paths, keep this fork's version.

## Still to change before any binary leaves this machine

- The app name, bundle ID and update feed are still upstream's (TRADEMARKS.md).
