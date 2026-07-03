# Bootstrap guide

`scripts/bootstrap.sh` applies everything a template can't ship as files.
This page is the manual fallback (GitHub UI / raw `gh` steps) for every
phase, plus the flag reference and troubleshooting.

Run the script when you can — it's idempotent, so re-running it later syncs
label drift back to what's declared in `.github/labels.yml`. The branch
ruleset (`.github/rulesets/main-branch.json`) is create-once, not synced:
re-running skips phase 7 if `main-branch-protection` already exists. To pick
up ruleset changes, delete the existing ruleset on GitHub first (see phase 7
below), then re-run.

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print every action that would be taken; execute nothing. |
| `--yes` | No prompts; accept defaults for every phase. |
| `--prune` | Delete undeclared repo labels without prompting (the default answer is already yes; use this to skip the prompt in scripts/CI). |
| `--skip-project` | Skip Project creation and field setup (phase 4). |
| `--keep-template-docs` | Skip de-templating (phase 8); keep `docs/template/` and the starter README. |
| `--help` | Show usage and exit. |

## Phases, and their manual equivalent

### 0. Preflight

Checks `gh` is installed and authenticated, that the token has `repo` and
`project` scopes, and detects the target repo via `gh repo view`.

Manual: `gh auth status`; if scopes are missing, `gh auth refresh -s repo -s project`.

### 1. Labels

Reads `.github/labels.yml` and creates-or-updates each label
(`gh label create --force`), then offers to delete repo labels not declared
in the file (GitHub's default labels — `bug`, `enhancement`, etc. — are
noise under this taxonomy, so pruning is the default answer).

Manual: **Settings → Labels**. Create each label from `.github/labels.yml`
by hand (name, color, description), then delete anything not on that list.

### 2. Issue types

Checks whether native issue types (`Bug`/`Feature`/`Task`) are available via
`gh api repos/{repo}/issue-types`. This endpoint isn't available on every
plan/org configuration.

Manual: **Organization settings → Repository → Issue types** (an
organization account is required — personal accounts don't expose native
issue types). If unavailable, the issue forms' `type:` key is silently
ignored by GitHub; the form still works, it just won't set a native type.
On personal-account repos, see the "Personal accounts" note in
`.github/PROJECT_FIELDS.md` for the label-based fallback.

### 3. Milestone

Creates a `v0.1.0` milestone ("First release") if one doesn't already exist
(checked across both open and closed milestones, so a closed v0.1.0 is not
recreated).

Manual: **Issues → Milestones → New milestone**, title `v0.1.0`.

### 4. Project

Creates a GitHub Project (v2) titled `<repo name> board`, links it to the
repository, and adds an `Effort` single-select field (`S`/`M`/`L`). Re-running
is safe: an existing link is left as-is and the `Effort` field is only
created if a field with that name isn't already present.

Manual: **Your profile → Projects → New project**, title it `<repo> board`,
then **⋯ → Link a repository** to attach it. Add a single-select field named
`Effort` with options `S`, `M`, `L` via **+ (add field)** on the board.

The script cannot create the `Status` field's non-default options or any
views — see `docs/setup/project-views.md` for that (manual, one-time) setup.

### 5. Repo settings

Sets merge strategy (squash + rebase allowed, merge commits disabled),
`delete_branch_on_merge`, issues on, wiki off.

Manual: **Settings → General → Pull Requests**: enable "Allow squash
merging" and "Allow rebase merging", disable "Allow merge commits", enable
"Automatically delete head branches". Under **Features**: Issues on, Wikis
off.

### 6. Actions PR permission

Enables Actions to create and approve pull requests — required for
release-please to open its release PR.

Manual: **Settings → Actions → General → Workflow permissions**, enable
"Allow GitHub Actions to create and approve pull requests". Without this,
release-please's workflow run fails with:

```text
GitHub Actions is not permitted to create or approve pull requests.
```

### 7. Ruleset

Imports `.github/rulesets/main-branch.json` as a repository ruleset named
`main-branch-protection`, if a ruleset with that name doesn't already exist.

Manual: **Settings → Rules → Rulesets → New ruleset → Import a ruleset**,
select `.github/rulesets/main-branch.json`. Review the imported rules (branch
deletion/force-push blocked, PR required, `ci` status check required) and
click **Create**.

### 8. De-template

One-time conversion from the template product to your project:

- `docs/template/README.starter.md` becomes `README.md`
- `docs/template/` is removed
- `CHANGELOG.md` resets to its 8-line seed
- `.release-please-manifest.json` is verified/rewritten to `{".": "0.0.0"}`

Guard: before touching anything, the script requires `README.md`,
`CHANGELOG.md`, `docs/template/`, and `.release-please-manifest.json` to be
clean in `git status` (no uncommitted changes). If any of those paths are
dirty, the phase is skipped with a warning — commit or stash first, then
re-run. This applies even under `--yes`.

Manual:

```bash
mv docs/template/README.starter.md README.md
rm -rf docs/template
cat > CHANGELOG.md <<'EOF'
# Changelog

All notable changes are recorded here by release-please (Conventional Commits
drive the entries — see docs/adr/ADR-0002-release-flow.md).

## Unreleased

No entries yet.
EOF
echo '{".": "0.0.0"}' > .release-please-manifest.json
```

`release-please-config.json` keeps `"release-as": "0.1.0"` after de-templating
— your first release is v0.1.0. Remove that key once the first release ships
so subsequent releases follow normal Conventional Commit version bumps.

The script does not run `git commit`. Review `git status` and commit
yourself: `git commit -m "chore: bootstrap repository"`.

## Troubleshooting

**"token scopes do not list 'project'"** — the default `gh auth login` token
doesn't request the `project` scope. Fix: `gh auth refresh -s project`, then
re-run.

**`issue-types` endpoint returns 404 / empty** — native issue types are an
organization-account feature; personal-account repos and some plans don't
expose them. The issue forms still work, but their `type:` key has no
effect until issue types are enabled at the org level (or the repo is
transferred into an org that has them).

**Ruleset name conflict** — if a ruleset named `main-branch-protection`
already exists, the script skips phase 7 rather than overwriting it (syncing
a ruleset means delete-then-rerun, since there's no partial-update path for
rule lists via `gh api`). To pick up changes from
`.github/rulesets/main-branch.json`: delete the existing ruleset in
**Settings → Rules → Rulesets**, then re-run `scripts/bootstrap.sh`.

**"GitHub Actions is not permitted to create or approve pull requests"** in
the release-please workflow run — phase 6 was skipped or declined. Enable it
per the manual step above, or re-run the script and accept the phase 6
prompt.

## See also

- `docs/setup/project-views.md` — manual Projects v2 Status options and views
- `.github/PROJECT_FIELDS.md` — the metadata single-home contract this setup enforces
- `docs/adr/ADR-0002-release-flow.md` — why release-please needs the Actions PR permission
