# GitHub Project OS

> An engineering operating system for GitHub-native, AI-agent-driven development.

[![CI](https://github.com/TzuH-Hsu/github-project-os/actions/workflows/ci.yml/badge.svg)](https://github.com/TzuH-Hsu/github-project-os/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A reusable, opinionated **template repository** for solo developers and small teams (1–3 people) who run their entire engineering process on GitHub — issues, projects, releases, CI, governance — with AI coding agents as first-class collaborators.

This is **not** a language or framework starter. It is the layer underneath: conventions, governance, automation, and reusable knowledge that work with any tech stack.

## What you get

- **Governance as code** — declarative labels, issue forms that set native issue types, a metadata single-home contract (`.github/PROJECT_FIELDS.md`), branch ruleset, PR template with a validation ladder.
- **AI collaboration layer** — a canonical `AGENTS.md` hub (Claude, Gemini, Copilot and others all point to it), an agent work queue convention (`agent-ok`), and session-handoff rules that keep context from rotting.
- **Skills** — focused, vendor-neutral knowledge modules under `skills/` that both humans and agents load on demand: issue writing, PR standards, release management, ADRs, anti-patterns, and more.
- **Automation without sprawl** — a small set of workflows (CI, issue labeling, link maintenance, release PRs) that call `make` targets, so you customize the Makefile and never touch the workflows.
- **A bootstrap script** — `scripts/bootstrap.sh` applies everything a template can't ship as files: labels, milestone, GitHub Project fields, repo settings, branch ruleset.

## Quick start

1. Click **Use this template** and create your repository.
2. Clone it, then run `scripts/bootstrap.sh` (requires the [GitHub CLI](https://cli.github.com/)) — it configures labels, Project, repo settings, and ruleset, then converts the repo from template mode to your project.
3. Read `AGENTS.md`, wire your test suite into the `test` target in the `Makefile`, and start working from issues.

Full setup guide (including manual, no-CLI steps): `docs/setup/bootstrap.md`.

## About the template itself

- Why each file exists: [docs/template/architecture.md](docs/template/architecture.md)
- Design principles: [docs/template/design-principles.md](docs/template/design-principles.md)
- Pulling future template updates into your project: [docs/template/upgrading.md](docs/template/upgrading.md)
- Decisions and rationale: [docs/adr/](docs/adr/README.md)

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Questions and problems go through [issues](https://github.com/TzuH-Hsu/github-project-os/issues).

## Status

The template is released and verified end to end (create from template → bootstrap → CI → release cut), and is usable today. Conventions may still evolve before `v1.0`, so check the [release notes](https://github.com/TzuH-Hsu/github-project-os/releases) for what changed — especially before pulling template updates into a project you have already adopted ([how to do that](docs/template/upgrading.md)).

## License

The template is [MIT](LICENSE). **Your repository does not have to be.**
Bootstrap phase 9 makes you choose — MIT under your own name, a proprietary /
all-rights-reserved notice for client and commissioned work, or decide later —
and records the scaffolding's MIT attribution in `NOTICE`, which you keep
either way. See [docs/setup/licensing.md](docs/setup/licensing.md).
