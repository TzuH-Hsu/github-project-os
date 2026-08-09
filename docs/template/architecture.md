# Architecture ledger

> Template-product documentation — removed from your copy by the bootstrap de-template step.

Why each piece of this repository exists, and what it costs to keep. A component that can't justify its row here gets removed (see [design principles](design-principles.md)).

## Ledger

| Component | Purpose | Maintenance cost |
| --- | --- | --- |
| `AGENTS.md` | Canonical agent/contributor contract; hub of the pointer files | Update when conventions change; index checked by `make check` |
| `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` | Per-agent entry points (≤10 lines each) | Near zero — pointers only |
| `skills/` (15 modules) | On-demand knowledge for humans + agents | Content reviews; consistency enforced by `scripts/check-skills.sh` |
| `.github/PROJECT_FIELDS.md` | Metadata single-home authority map | Update only when taxonomy changes (rare, ADR-worthy) |
| `.github/labels.yml` | Labels as code; bootstrap re-run = sync | Edit alongside label changes; allowlist in `issue-labeler.yml` must match |
| `.github/ISSUE_TEMPLATE/` (3 forms) | Set native types; feed the labeler | Sync option lists with `labels.yml` |
| `.github/PULL_REQUEST_TEMPLATE.md` | Validation ladder + RISK convention at point of use | Near zero |
| `.github/workflows/ci.yml` | L0 gate; installs tools via `make ci-tools`, runs `make ci-pr`. The only required status check — see its header before touching `on:` | SHA-pin bumps via Dependabot |
| `.github/workflows/issue-labeler.yml` | Form selections → labels (single-home preserving) | Allowlist sync with `labels.yml` |
| `.github/workflows/maintenance.yml` | Weekly drift detectors: external link check + CI tool version check | Near zero |
| `.github/workflows/release-please.yml` + configs | Human-gated release automation (ADR-0002) | Action SHA bumps; `release-as` removed after first release |
| `.github/rulesets/main-branch.json` | Importable branch protection (PR + green `ci` required) | Near zero |
| `Makefile` | The only executable contract; adopter customization point | Grows with adopter stack, not with the template |
| `scripts/bootstrap.sh` | Applies everything a template can't ship as files; idempotent sync | Highest-cost component — E2E-verified each release (below) |
| `scripts/check-*.sh` | Self-consistency: skills index, local-md hygiene | Near zero |
| `scripts/install-ci-tools.sh` | Checksum-verified CI tool installs; single home for all five tool version pins, shared by `ci.yml` and `maintenance.yml` via `make ci-tools` | Hand-bump a pin when the drift check flags it |
| `scripts/check-tool-versions.sh` | Diffs those pins against upstream weekly and fails on drift — Dependabot cannot see them, so nothing else would | Near zero; add a row when a tool is added |
| `docs/adr/` | Decision records; the "why" layer | Grows slowly by trigger criteria |
| `docs/setup/` | Bootstrap reference + manual fallback | Update alongside `bootstrap.sh` |
| `docs/template/` | Template-product meta (this dir); deleted on adoption | Only exists upstream |

## Release exit checklist (template releases)

Before merging a release PR:

1. `make verify` green locally; CI green on `main`.
2. Scratch-repo E2E: create a repo from the template (`gh repo create <scratch> --template ...`), run `scripts/bootstrap.sh --dry-run` then live, re-run to confirm idempotence, run the de-template phase, open one issue per form (native type + labels land), open a trivial PR (CI runs, ruleset enforces), then delete the scratch repo.
3. Private-info sweep: `grep -riE '<maintainer personal strings>' .` returns nothing (see release-management skill).
4. Merge release PR (human), then add the hand-written TLDR to the GitHub Release.
