# Project Name

> One-line description of what this project does and for whom.

Built on [GitHub Project OS](https://github.com/TzuH-Hsu/github-project-os) — GitHub-native project management with AI agents as first-class collaborators.

<!-- Paths below are written for this file's final location at the repository root (the bootstrap de-template step moves it there). -->

## Getting started

<!-- Your stack's setup steps: prerequisites, install, run. -->

```bash
make help     # all targets
make verify   # lint + tests — run before every PR
```

## How this repository works

- **Conventions** (branching, commits, PRs, validation ladder): `AGENTS.md` is canonical; `CONTRIBUTING.md` is the human guide.
- **Issues** go through the issue forms; metadata rules live in `.github/PROJECT_FIELDS.md`.
- **Knowledge** lives in `skills/` (catalog: `skills/README.md`) — load what the task needs.
- **Releases** are cut by merging the release-please PR (human-gated) — see `docs/adr/ADR-0002-release-flow.md`.

## License

<!-- Your license. The template itself is MIT; your project may differ. -->
