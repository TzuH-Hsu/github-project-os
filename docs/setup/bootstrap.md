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
| `--license MODE` | Answer phase 9 non-interactively: `mit`, `proprietary` or `defer`. Without it, `--yes` defers and files the decision first. |
| `--keep-template-docs` | Skip de-templating (phase 10); keep `docs/template/` and the starter README. |
| `--help` | Show usage and exit. |

## Phases, and their manual equivalent

### 0. Preflight

Checks `gh` is installed and authenticated, that the token has `repo` and
`project` scopes, and detects the target repo via `gh repo view`.

Manual: `gh auth status`; if scopes are missing, `gh auth refresh -s repo -s project`.

**If you created the repo with `gh repo create --template`, wait before
cloning.** GitHub copies the template contents asynchronously and `gh repo
create` returns before that copy finishes, so an immediate clone can hand you a
repo with no commits and an empty working tree — after which every phase below
fails on a repo that looks like it was never created from a template. It has
been reported against `gh` repeatedly over the years (cli/cli#2290,
cli/cli#5142, cli/cli#7055), and `--clone` is the variant that fails most
often. Poll for the first commit, then clone:

```bash
REPO=OWNER/NEW-REPO   # the repo you just created from the template

# Fail fast on a typo or missing access: the repo record exists immediately,
# only its contents are asynchronous. This GATES the poll -- without it, a
# mistyped name burns all 30 attempts and then reports a misleading
# "template copy" timeout.
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "no such repo, or no access: $REPO" >&2
else
  sha=""
  n=0
  while [ "$n" -lt 30 ]; do
    if sha="$(gh api "repos/$REPO/commits?per_page=1" --jq '.[0].sha' 2>/dev/null)" && [ -n "$sha" ]; then
      break
    fi
    sha=""
    n=$((n + 1))
    sleep 2
  done

  if [ -n "$sha" ]; then
    gh repo clone "$REPO"
  else
    echo "still no commits after ~60s -- check https://github.com/$REPO" >&2
  fi
fi
```

Bounded at roughly 60 seconds, never loops forever, and runs on bash 3.2 (macOS
`/bin/bash`): no `mapfile`, no associative arrays, no `timeout(1)`. It is also
safe to paste into an interactive shell — no `exit`, no dependence on `set -e`.

Two details are load-bearing. Polling for a commit rather than for
`repos/{owner}/{repo}/contents` matters because a bare `contents` 404 cannot
distinguish "not ready yet" from "wrong name" or "no access"; the `gh repo view`
line above separates those. And the `&&` ordering matters because `gh api`
prints its JSON error body to *stdout* on an HTTP error, so `sha` would
otherwise hold that body — the non-zero exit short-circuits before the emptiness
test is ever reached.

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

Manual: **Organization settings → Repository → Issue types** on an org repo, or
**Settings → Issue types** on a personal account — these began as an
organization-only feature and have since been rolled out to user accounts, so
check the endpoint rather than assuming from your account type. If they really
are unavailable, the issue forms' `type:` key is silently ignored by GitHub; the
form still works, it just won't set a native type.
On a personal account you then choose one of two things, and the phase tells
you which you currently have:

1. **Accept no coarse Type.** Subtypes, priority, area, status and milestone all
   still work; you just cannot filter Bug vs Feature. Nothing to configure.
2. **Adopt the label fallback.** Uncomment the `type:bug` / `type:feature` block
   in `.github/labels.yml` and re-run. Labels become the *one* home for coarse
   Type.

They ship commented out so an organization repo — which already has native
issue types — cannot end up holding both homes at once. The phase checks that
direction too: with native types available *and* the fallback declared, it
reports a single-home violation. See "Personal accounts" in
`.github/PROJECT_FIELDS.md`.

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

### 9. Licence

**The one phase you cannot safely skim.** Until you answer it, your repository
carries the *template's* licence — MIT, copyright the template author — and
that is almost certainly not what you want.

MIT is an irrevocable grant: anyone who obtains a copy may use, modify,
publish, distribute, sublicense and **sell** it, and publishing it once cannot
be undone. For client or commissioned work that usually conflicts with your
contract, which typically transfers copyright on final payment — an MIT file in
the delivered repository grants the client, and everyone else, far more than
that, before you have been paid. And even if you do want MIT, the copyright
line has to name you.

Three answers, with no default — a bare Enter re-asks:

1. **MIT under your name.** Keeps the MIT terms, rewrites the copyright line.
2. **Proprietary / all rights reserved.** For client, commissioned and
   closed-source work. Replaces `LICENSE` with an all-rights-reserved notice
   that defers to your commission agreement rather than pretending to be one.
3. **Decide later.** Leaves `LICENSE` untouched and puts the decision at the
   **top** of the remaining manual steps, marked `!`.

Anything else — Apache-2.0, GPL, BUSL — is answer 3: supply the text yourself.
The script ships no other licence bodies.

**Both writing answers also create `NOTICE`, and this is not optional.**
Substantial parts of this template ship verbatim in your repository
(`scripts/bootstrap.sh` alone is over 900 lines, plus the workflows, the
Makefile, and every skill), and MIT requires its copyright and permission
notice to travel with them. Rewriting `LICENSE` without writing `NOTICE` would
delete the only copy of that notice from your repository — swapping a licensing
mistake for a licence violation. `NOTICE` is where the attribution lives, and
it stays even if you relicense everything else.

Under `--yes` the phase writes **nothing** and files the decision as the first
manual step, because silently keeping the template author's MIT is the bug this
phase exists to prevent. `--license mit|proprietary|defer` answers it
non-interactively. Re-running after you have decided is a no-op: the phase
recognises that `LICENSE` no longer carries the template's copyright line and
leaves it alone. If `LICENSE` or `NOTICE` have uncommitted changes the phase
skips entirely, even under `--yes`.

Manual: see `docs/setup/licensing.md`, which carries both file bodies verbatim
and the reasoning behind them.

### 10. De-template

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

**Cloned repo is empty, or bootstrap says `AGENTS.md and .git not found`** —
`gh repo create --template` returns before GitHub finishes copying the template,
so the clone can predate the contents. See the wait loop in "0. Preflight" to
prevent it. To recover a clone you already made:

```bash
git fetch origin
git reset --hard origin/main
```

That discards uncommitted work — only run it on a clone you have not started
editing.

If you cloned while the repo had *no* commits, `origin/main` does not exist
locally yet. Once GitHub finishes the copy, `git fetch origin` will create it —
but your local `HEAD` is unborn and may not be on `main`, so check before
resetting:

```bash
git fetch origin
git rev-parse --verify origin/main >/dev/null 2>&1 \
  && git checkout -B main --track origin/main \
  || echo "remote still has no commits - wait, or delete the directory and clone again" >&2
```

**Security settings come back empty / "could not read"** — the
`security_and_analysis` object is only populated for callers with admin
permission on the repository, so a token without it sees nothing rather than
seeing "disabled". Phase 6 reports this as unknown and emits a manual step
instead of guessing. Check `gh auth status`, and re-run once the token has
admin, or set the four toggles by hand in **Settings → Advanced Security**.

**"token scopes do not list 'project'"** — the default `gh auth login` token
doesn't request the `project` scope. Fix: `gh auth refresh -s project`, then
re-run.

**`issue-types` endpoint returns 404 / empty** — the repo has no native issue
types, so the issue forms' `type:` key has no effect. These began as an
organization-only feature and have since been rolled out to personal accounts
as well, so check **Settings → Issue types** (or the org equivalent) before
concluding you cannot have them. If they genuinely are unavailable and you want
a queryable coarse Type, uncomment the `type:bug` / `type:feature` block in
`.github/labels.yml` and re-run — those labels are applied by hand, never by the
labeler workflow.

**Ruleset name conflict** — if a ruleset named `main-branch-protection`
already exists, the script skips phase 8 rather than overwriting it (syncing
a ruleset means delete-then-rerun, since there's no partial-update path for
rule lists via `gh api`). To pick up changes from
`.github/rulesets/main-branch.json`: delete the existing ruleset in
**Settings → Rules → Rulesets**, then re-run `scripts/bootstrap.sh`.

**"GitHub Actions is not permitted to create or approve pull requests"** in
the release-please workflow run — phase 7 was skipped or declined. Enable it
per the manual step above, or re-run the script and accept the phase 7
prompt.

## See also

- `docs/setup/project-views.md` — manual Project views setup, plus the manual Status-options fallback for when bootstrap warns
- `.github/PROJECT_FIELDS.md` — the metadata single-home contract this setup enforces
- `docs/adr/ADR-0002-release-flow.md` — why release-please needs the Actions PR permission
