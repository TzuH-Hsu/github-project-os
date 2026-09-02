# Bootstrap guide

`scripts/bootstrap.sh` applies everything a template can't ship as files.
This page is the manual fallback (GitHub UI / raw `gh` steps) for every
phase, plus the flag reference and troubleshooting.

Run the script when you can — it's idempotent, so re-running it later syncs
label drift back to what's declared in `.github/labels.yml`. The branch
ruleset (`.github/rulesets/main-branch.json`) is create-once, not synced:
re-running skips phase 8 if `main-branch-protection` already exists. To pick
up ruleset changes, delete the existing ruleset on GitHub first (see phase 8
below), then re-run.

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print every action that would be taken; execute nothing. |
| `--yes` | No prompts; accept defaults for every phase. |
| `--prune` | Delete undeclared repo labels without prompting (the default answer is already yes; use this to skip the prompt in scripts/CI). |
| `--skip-project` | Skip Project creation and field setup (phase 4). |
| `--keep-template-docs` | Skip de-templating (phase 9); keep `docs/template/` and the starter README. |
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
repository, adds an `Effort` single-select field (`S`/`M`/`L`), and — on the
project this run itself just created — sets the `Status` field's options to
the single-home contract's target set
(`Backlog`/`Ready`/`In Progress`/`In Review`/`Blocked`/`Done`) via the
GraphQL `updateProjectV2Field` mutation. Re-running is safe: an existing
link is left as-is, the `Effort` field is only created if a field with that
name isn't already present, and Status options are never rewritten on a
project that pre-existed the run.

**Status options — automatic only on a just-created project:** the script
reads the current Status option names (in order) via `gh project
field-list`:

- Already the target set → prints a skip line, no mutation (idempotent).
- Project created by this same bootstrap run (its Status necessarily still
  holds GitHub's defaults `Todo`/`In Progress`/`Done`, and a just-created
  board cannot have items yet) → rewrites the options to the target set via
  `updateProjectV2Field(singleSelectOptions:...)`.
- Project pre-existed the run — **even if its options look like the
  pristine defaults** — or the options were customized → the script leaves
  the field alone and prints a WARN + a MANUAL note. Rewriting options
  assigns new option IDs, which would silently orphan the Status values of
  any items already on the board, so auto-rewrite only ever fires on a
  board this run created.

Manual: **Your profile → Projects → New project**, title it `<repo> board`,
then **⋯ → Link a repository** to attach it. Add a single-select field named
`Effort` with options `S`, `M`, `L` via **+ (add field)** on the board. If
bootstrap warned about a pre-existing project or custom Status options (or
you want to set them by hand), see `docs/setup/project-views.md`.

The script still cannot create Project views — that remains a manual,
one-time step; see `docs/setup/project-views.md`.

### 5. Repo settings

Sets squash as the only merge strategy, pins the squash commit message to the
PR title and body, and turns on `delete_branch_on_merge`, `allow_update_branch`,
issues, and wiki off.

The two squash-message settings are not cosmetic. GitHub's defaults are
`COMMIT_OR_PR_TITLE` and `COMMIT_MESSAGES`, which mean the PR title is used
only when a PR has two or more commits, and every branch commit message is
concatenated into the `main` commit body. Both break promises this repository
makes elsewhere: `AGENTS.md` states the PR title becomes the commit message on
`main`, and release-please parses that commit body for further Conventional
Commits and `BREAKING-CHANGE` footers — so a stray `feat:` or `fix:` on a
branch can produce a phantom changelog entry or an unintended version bump.

Rebase is off because nothing needs it. The release PR is merged by a human
like any other PR (see `docs/adr/ADR-0002-release-flow.md`), not by
release-please, and squash is what release-please recommends for the linear
history it parses.

Manual: **Settings → General → Pull Requests** — enable "Allow squash merging"
and, under it, set the default commit message dropdown to **"Pull request title
and description"**; disable "Allow merge commits" and "Allow rebase merging";
enable "Always suggest updating pull request branches" and "Automatically
delete head branches". Under **Features**: Issues on, Wikis off.

### 6. Security

Reports repository visibility and the state of secret scanning, push
protection, Dependabot alerts and Dependabot security updates, then offers to
enable whatever is off — subject to one rule.

**The only settings bootstrap enables here are the ones that are free.**
Anything with a billing consequence is reported and handed back to you as a
manual step. Concretely:

- **Public repo** — secret scanning and push protection are free, so the script
  offers to enable them. Going public does *not* switch them on by itself;
  push protection in particular has to be enabled explicitly.
- **Private or internal repo** — the script will **not** enable secret scanning
  for you at all, under any flag. There it needs a paid GitHub Advanced
  Security / Secret Protection seat, and committing your account to a
  per-committer charge is not a setup step. You get the current state, an
  explanation, and a manual step.
- **Dependabot alerts and security updates** — free on every plan, so they are
  offered regardless of visibility. `.github/dependabot.yml` already assumes
  both are on; until now nothing verified that.

The phase never changes repository visibility and never offers to. Going from
private to public erases stars and watchers and publishes your entire Actions
history — a one-way door, not something a setup script should ask about
in passing.

Two states the summary distinguishes that the GitHub UI blurs: settings that
are *unreadable* (your token lacks admin on the repo) are reported as unknown
rather than as disabled, and Dependabot security updates that are enabled but
**paused** are called out, because paused means no fix PR will ever open.

Since every read runs for real even under `--dry-run`,
`scripts/bootstrap.sh --dry-run` doubles as a zero-risk security audit of an
existing repository.

**One thing that sounds alarming and is not:** GitHub's documentation lists
"all push rulesets will be disabled" among the consequences of making a repo
public. This template's ruleset (`.github/rulesets/main-branch.json`) has
`"target": "branch"`, not `"push"`, so it is unaffected — your `main`
protection survives a visibility change.

Manual: **Settings → Advanced Security**. Enable "Secret scanning" and, under
it, "Push protection". Enable "Dependabot alerts" and "Dependabot security
updates". On a private repo the first two require a Secret Protection licence;
the Dependabot pair are free everywhere.

### 7. Actions PR permission

Enables Actions to create and approve pull requests — required for
release-please to open its release PR.

Manual: **Settings → Actions → General → Workflow permissions**, enable
"Allow GitHub Actions to create and approve pull requests". Without this,
release-please's workflow run fails with:

```text
GitHub Actions is not permitted to create or approve pull requests.
```

### 8. Ruleset

Imports `.github/rulesets/main-branch.json` as a repository ruleset named
`main-branch-protection`, if a ruleset with that name doesn't already exist.

**Admin bypass note:** The ruleset is configured with `bypass_mode: always`, which allows repository administrators to push directly to `main` without enforcement — they see a bypass notice instead of a block. This protects against non-admin pushes and accidental force-push/deletion. Solo maintainers who want the rules to bind their own pushes too should remove the admin bypass actor in **GitHub Settings → Rules → Rulesets → main-branch-protection → Bypass actors**.

Manual: **Settings → Rules → Rulesets → New ruleset → Import a ruleset**,
select `.github/rulesets/main-branch.json`. Review the imported rules (branch
deletion/force-push blocked, PR required, `ci` status check required) and
click **Create**.

### 9. De-template

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

**Note on first release:** The `chore: bootstrap repository` commit does not trigger a release PR. release-please only reacts to releasable Conventional Commit types (`feat`, `fix`, or commits with `!` / `BREAKING CHANGE`); the first `feat:` or `fix:` commit after bootstrap triggers the v0.1.0 release PR. To cut a release immediately, add a `Release-As: 0.1.0` footer to the commit message or manually trigger release-please.

## Troubleshooting

**Security settings come back empty / "could not read"** — the
`security_and_analysis` object is only populated for callers with admin
permission on the repository, so a token without it sees nothing rather than
seeing "disabled". Phase 6 reports this as unknown and emits a manual step
instead of guessing. Check `gh auth status`, and re-run once the token has
admin, or set the four toggles by hand in **Settings → Advanced Security**.

**"token scopes do not list 'project'"** — the default `gh auth login` token
doesn't request the `project` scope. Fix: `gh auth refresh -s project`, then
re-run.

**`issue-types` endpoint returns 404 / empty** — native issue types are an
organization-account feature; personal-account repos and some plans don't
expose them. The issue forms still work, but their `type:` key has no
effect until issue types are enabled at the org level (or the repo is
transferred into an org that has them).

**Ruleset name conflict** — if a ruleset named `main-branch-protection`
already exists, the script skips phase 8 rather than overwriting it (syncing
a ruleset means delete-then-rerun, since there's no partial-update path for
rule lists via `gh api`). To pick up changes from
`.github/rulesets/main-branch.json`: delete the existing ruleset in
**Settings → Rules → Rulesets**, then re-run `scripts/bootstrap.sh`.

**"GitHub Actions is not permitted to create or approve pull requests"** in
the release-please workflow run — phase 6 was skipped or declined. Enable it
per the manual step above, or re-run the script and accept the phase 6
prompt.

## See also

- `docs/setup/project-views.md` — manual Project views setup, plus the manual Status-options fallback for when bootstrap warns
- `.github/PROJECT_FIELDS.md` — the metadata single-home contract this setup enforces
- `docs/adr/ADR-0002-release-flow.md` — why release-please needs the Actions PR permission
