# AGENTS.md

Canonical instructions for AI coding agents — and the humans working alongside them — in this repository.

Agent-specific entry files (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`) are thin pointers to this file. **This file is the single source of truth.** If guidance conflicts anywhere else, AGENTS.md wins.

## Operating rules (read first)

1. Work from an issue. If no issue exists for what you are about to do, create one first (see `skills/issue-writing/`).
2. Never commit directly to `main`. Branch as `<type>/<issue#>-<slug>` (e.g. `feat/42-label-sync`), open a PR.
3. Follow the metadata single-home contract in `.github/PROJECT_FIELDS.md` — every attribute (type, priority, area, status, version) lives in exactly one place. Never dual-write.
4. Run `make verify` before opening or updating a PR.
5. Declare skipped validation levels in the PR body: `RISK: <level> not run — <reason>`. Never skip silently.
6. Never commit `*.local.md` files, secrets, or `.env*` files (only `.env.example` is allowed).
7. Load skills on demand (see index below). Do not bulk-load every skill into context.

## Build and validation

The Makefile is the only executable contract in this repository. CI calls make targets; customize the Makefile, never the workflows.

| Level | Name | Command | When required |
| --- | --- | --- | --- |
| L0 | static | `make lint` | every PR |
| L1 | unit | `make test` | every PR |
| L2 | integration | adopter-defined | when the change touches component boundaries |
| L3 | e2e / preview | adopter-defined | user-visible changes |
| L4+ | extensions | adopter-defined | domain-specific (see `skills/validation-ladder/`) |

- `make verify` = L0 + L1 — the canonical local gate before any PR.
- `make help` lists all targets.
- Pick validation depth by blast radius; a level that applies but cannot run becomes a `RISK:` line in the PR.

## Repository layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | This file — canonical agent + contributor instructions |
| `.github/` | Governance: workflows, issue forms, PR template, `PROJECT_FIELDS.md`, `labels.yml`, rulesets |
| `skills/` | Reusable knowledge modules (one directory per skill, `SKILL.md` inside) |
| `docs/adr/` | Architecture Decision Records |
| `docs/setup/` | Bootstrap and GitHub configuration guides |
| `scripts/` | Bootstrap and self-consistency check scripts |
| `Makefile` | Canonical target contract (validation ladder entry points) |

## Workflow

1. **Issue** — created via issue forms; native type (Bug/Feature/Task) is set by the form; labels for priority/area follow `.github/PROJECT_FIELDS.md`.
2. **Branch** — `<type>/<issue#>-<slug>`; types mirror Conventional Commit types (`feat`, `fix`, `docs`, `chore`, `refactor`, `ci`).
3. **Commits** — Conventional Commits, English, imperative (`feat: add label sync phase to bootstrap`).
4. **PR** — English title in Conventional Commit format; body follows the PR template: summary, linked issue (`Closes #N`), validation ladder checkboxes, `RISK:` lines, rollback notes.
5. **Merge** — squash merge; the PR title becomes the commit message on `main`.

## AI agent conventions

- **Work queue**: issues labeled `agent-ok` with Project status `Ready` are self-service — an agent may pick one up without asking. Anything not labeled `agent-ok` needs an explicit human request.
- **Audit trail**: label PRs you author with `by-agent`.
- **Capability boundaries**: agents may manage issues, labels, milestones, and Project items via `gh`; agents must NOT perform destructive operations (deleting Project fields, force-pushing, rewriting history, changing repo settings) without explicit human approval in the conversation.
- **Session handoff**: long-running work may keep exactly one gitignored `HANDOVER.local.md` (hard cap ~150 lines, rewrite — don't append — at session end). Durable knowledge gets promoted to issues, ADRs, or skills, then deleted from the handoff file. See `skills/context-handoff/`.

## Skills index

Load a skill only when its "load when" condition matches your current task.

| Skill | Load when |
| --- | --- |
| _(index is wired as skills land — see `skills/README.md`)_ | _(catalog pending)_ |

## Pointers

- Process and conventions for humans: `CONTRIBUTING.md`
- Metadata contract: `.github/PROJECT_FIELDS.md`
- Decisions and rationale: `docs/adr/`
- Security policy: `SECURITY.md`
