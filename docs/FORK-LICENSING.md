# Fork licensing rules

Not legal advice. Audited 2026-10-13 against upstream's LICENSE, TRADEMARKS.md, CONTRIBUTING.md and docs/AI-CONTRIBUTIONS.md.

## Carried PRs (`scripts/adopted-prs.txt`)

- Contributors submit under upstream's GPL-3.0-or-later terms, so carrying their commits is allowed.
- Keep each author's name on the cherry-pick and credit them in the README's adopted list (generated).
- Before adding a number, run `scripts/check-carried-licensing.sh <pr>`. It fails on any added license or copyright line other than upstream's own header, mentions of another source, non-system imports, or dependency changes. Fix or reject on a finding.
- Checked 2026-10-13, all clean (Apple frameworks only, upstream header only): #1879, #2909, #3010, #2966.

## GPL duties

- Keep `LICENSE` and every source file's copyright header intact; `scripts/check-carried-licensing.sh` fails if `LICENSE` or `TRADEMARKS.md` differ from upstream.
- Publishing a binary requires offering the source. The public repo covers that. Before any binary leaves this machine, also replace the Vorssaint name, bundle ID, icon and update feed (TRADEMARKS.md).

## Open decisions

- Upstream's `logo.svg`, `logo-dark.svg` and `Resources/Brand` files are not GPL-licensed. Ask the maintainer or delete the unused ones; never reuse them for fork branding.
