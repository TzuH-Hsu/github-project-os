#!/usr/bin/env bash
# bootstrap.sh — one-time (and re-runnable) setup for a repo created from the
# "GitHub Project OS" template. Applies everything a template can't ship as
# files: labels, milestone, GitHub Project fields, repo settings, security
# settings, ruleset,
# and (once) converts the repo from template docs to your project docs.
#
# Idempotent: re-running syncs label state to what's declared in
# .github/labels.yml. The branch ruleset is create-once, not synced: if
# main-branch-protection already exists, phase 8 is skipped rather than
# updated — delete the ruleset on GitHub and re-run to pick up changes to
# .github/rulesets/main-branch.json.
#
# Usage: scripts/bootstrap.sh [--dry-run] [--yes] [--prune] [--license MODE]
#                              [--skip-project] [--keep-template-docs] [--help]
#
# bash 3.2 portable (macOS default /bin/bash). No arrays-of-arrays, no
# associative arrays, no `mapfile`.

set -euo pipefail

# --- globals ---
DRY_RUN=0
ASSUME_YES=0
PRUNE_LABELS=0
SKIP_PROJECT=0
KEEP_TEMPLATE_DOCS=0
LICENSE_MODE=""
LICENSE_CHOICE=""
LICENSE_HOLDER=""
REPO=""       # owner/name
OWNER=""
REPO_NAME=""

# Phase result tracking (parallel newline-delimited lists; bash 3.2 has no
# associative arrays).
PHASE_NAMES=""
PHASE_RESULTS=""
MANUAL_STEPS=""
# Manual steps that are unsafe to defer. Rendered ABOVE MANUAL_STEPS in the
# summary regardless of which phase recorded them, because MANUAL_STEPS is
# appended in phase order and the licence decision runs second-to-last.
# Reserved for steps where shipping without doing them is a defect, not an
# inconvenience.
MANUAL_URGENT=""

# --- colors (disabled when not a tty) ---
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

ok()     { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
doing()  { printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$1"; }
skip()   { printf '%sskip%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
warn()   { printf '%sWARN%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
fail()   { printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
manual() { printf '%sMANUAL%s %s\n' "$C_BOLD" "$C_RESET" "$1"; MANUAL_STEPS="${MANUAL_STEPS}- ${1}
"; }
manual_urgent() { printf '%sMANUAL (do this first)%s %s\n' "$C_RED" "$C_RESET" "$1"; MANUAL_URGENT="${MANUAL_URGENT}- ${1}
"; }

record_phase() {
  # record_phase <name> <result: ok|warn|fail|skip>
  PHASE_NAMES="${PHASE_NAMES}${1}
"
  PHASE_RESULTS="${PHASE_RESULTS}${2}
"
}

# run_or_dry is the single choke point for every mutating gh call. Every
# `gh` call that creates/updates/deletes state MUST go through this; in
# --dry-run mode it only prints the command and never executes it.
run_or_dry() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s[dry-run]%s would run: %s\n' "$C_YELLOW" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [options]

One-time (and re-runnable) setup for a repo created from the
"GitHub Project OS" template. Requires the GitHub CLI (gh), authenticated.

Options:
  --dry-run             Print every action that would be taken; execute nothing.
  --yes                 Assume "yes" to all prompts; accept defaults, no interaction.
  --prune               Delete repo labels not declared in .github/labels.yml,
                         without prompting (implies the default prune behavior).
  --skip-project        Skip phase 4 (GitHub Project creation / field setup).
  --license MODE        Choose the licence non-interactively: mit | proprietary | defer.
                        Without it, --yes defers and files the decision first.
  --keep-template-docs  Skip phase 10 (de-templating); keep docs/template/ and
                         the starter README in place.
  --help                Show this help and exit.

Phases:
  0. Preflight          gh installed, authenticated, scopes, target repo
  1. Labels             sync .github/labels.yml, prompt to prune extras
  2. Issue types        check native Bug/Feature/Task availability
  3. Milestone          create v0.1.0 if missing
  4. Project            create Project v2 board + Effort field (see --skip-project)
  5. Repo settings       merge strategy, delete-branch-on-merge, wiki off
  6. Security            secret scanning + push protection (public repos), Dependabot alerts
  7. Actions permission  enable Actions to create/approve PRs (release-please)
  8. Ruleset             import .github/rulesets/main-branch.json
  9. Licence             choose YOUR licence; write NOTICE attribution
 10. De-template         convert repo from template docs to your project (see --keep-template-docs)

Docs: docs/setup/bootstrap.md (manual fallback + reference for every phase).
EOF
}

# --- arg parsing ---
# True only when this file is executed, not sourced. Sourcing must define
# functions and touch nothing else: without this the top-level argument parser
# below consumes the CALLER's positional parameters, and an ordinary caller
# argument is treated as an unknown bootstrap option and calls exit 1 -- which
# terminates the sourcing shell.
#
# Caveat that remains by design: sourcing still applies `set -euo pipefail` to
# the caller. Source from a subshell if that matters.
bootstrap_is_main() { [ "${BASH_SOURCE[0]}" = "$0" ]; }

if bootstrap_is_main; then
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --prune) PRUNE_LABELS=1 ;;
    --skip-project) SKIP_PROJECT=1 ;;
    --keep-template-docs) KEEP_TEMPLATE_DOCS=1 ;;
    --license)
      shift
      if [ $# -eq 0 ]; then
        fail "--license requires a value: mit | proprietary | defer"
        exit 1
      fi
      case "$1" in
        mit|proprietary|defer) LICENSE_MODE="$1" ;;
        *) fail "--license: unknown value '$1' (use mit, proprietary, or defer)"; exit 1 ;;
      esac
      ;;
    --help|-h) usage; exit 0 ;;
    *)
      fail "unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done
fi

# confirm <prompt> <default: y|n> → returns 0 for yes, 1 for no. Always
# yes under --yes.
confirm() {
  local prompt="$1" default="$2" reply
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ "$default" = "y" ]; then
    printf '%s [Y/n] ' "$prompt"
  else
    printf '%s [y/N] ' "$prompt"
  fi
  read -r reply || reply=""
  if [ -z "$reply" ]; then
    reply="$default"
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Phase 0 — Preflight ---

phase_preflight() {
  doing "Phase 0: preflight checks"

  if [ ! -f "AGENTS.md" ] || [ ! -d ".git" ]; then
    fail "must be run from the repository root (AGENTS.md and .git not found here)"
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is not installed — https://cli.github.com/"
    exit 1
  fi
  ok "gh CLI found ($(gh --version | head -n1))"
  if ! gh auth status >/dev/null 2>&1; then
    fail "gh is not authenticated — run: gh auth login"
    exit 1
  fi
  ok "gh is authenticated"

  # Parse `gh auth status` for granted scopes, e.g.:
  #   "  Token scopes: 'repo', 'read:org', 'workflow'"
  local scopes_line
  scopes_line="$(gh auth status 2>&1 | grep -i 'Token scopes' || true)"
  if printf '%s' "$scopes_line" | grep -q "'project'"; then
    ok "token has 'project' scope"
  else
    warn "token scopes do not list 'project' — Project creation (phase 4) may fail"
    warn "fix: gh auth refresh -s project"
  fi
  if printf '%s' "$scopes_line" | grep -Eq "'repo'"; then
    ok "token has 'repo' scope"
  else
    warn "token scopes do not clearly list 'repo' — some phases may fail"
    warn "fix: gh auth refresh -s repo"
  fi

  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  if [ -z "$REPO" ]; then
    fail "could not detect target repo via 'gh repo view' — are you inside a GitHub-hosted git repo with a remote?"
    exit 1
  fi
  OWNER="${REPO%%/*}"
  REPO_NAME="${REPO##*/}"
  printf '\n%sTarget repository:%s %s\n\n' "$C_BOLD" "$C_RESET" "$REPO"
  [ "$DRY_RUN" -eq 1 ] && ok "dry-run mode — no mutations will be executed"

  if ! confirm "Proceed with bootstrap against ${REPO}?" "y"; then
    fail "aborted by user"
    exit 1
  fi
  record_phase "0. Preflight" "ok"
}

# --- Phase 1 — Labels ---

# parse_labels_yml reads .github/labels.yml (fixed structure) and emits
# "name<TAB>color<TAB>description" lines. No yq dependency — the file format
# is a flat list of `- name: / color: / description:` entries.
#
# Supported format ONLY: exactly one `- name:`, `color:`, `description:` key
# per entry, each on its own unquoted single line, in that order. YAML
# quoting (`name: "foo"`), multi-line block scalars (`description: |`),
# inline comments (`color: e4e669 # note`), and flow/inline mappings are
# NOT supported and will parse incorrectly or silently. Keep labels.yml to
# the flat format documented in its own header comment.
parse_labels_yml() {
  local file="$1"
  awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
      if (name != "") { print name "\t" color "\t" desc }
      name = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name)
      color = ""; desc = ""
      next
    }
    /^[[:space:]]*color:/ {
      color = $0
      sub(/^[[:space:]]*color:[[:space:]]*/, "", color)
      next
    }
    /^[[:space:]]*description:/ {
      desc = $0
      sub(/^[[:space:]]*description:[[:space:]]*/, "", desc)
      next
    }
    END {
      if (name != "") { print name "\t" color "\t" desc }
    }
  ' "$file"
}

phase_labels() {
  doing "Phase 1: labels (.github/labels.yml)"

  local labels_file=".github/labels.yml"
  if [ ! -f "$labels_file" ]; then
    warn "no ${labels_file} found — skipping label sync"
    record_phase "1. Labels" "skip"
    return
  fi

  local parsed
  parsed="$(parse_labels_yml "$labels_file")"

  if [ -z "$parsed" ]; then
    warn "${labels_file} parsed to zero labels — check its format"
    record_phase "1. Labels" "warn"
    return
  fi

  local declared_names=""
  local name color description
  while IFS=$'\t' read -r name color description; do
    [ -n "$name" ] || continue

    # Cheap validation: catch entries the awk parser mis-split (e.g. quoted
    # values, inline comments, multi-line scalars — see the format note atop
    # parse_labels_yml). A malformed color/name here means the file drifted
    # from the supported flat format, not that gh should be asked to guess.
    if [ -z "$color" ]; then
      fail "label '${name}': empty color in ${labels_file} — check format (see parse_labels_yml comment)"
      record_phase "1. Labels" "fail"
      return 1
    fi
    case "$color" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) : ;;
      *)
        fail "label '${name}': color '${color}' is not 6 hex digits in ${labels_file} — check format (see parse_labels_yml comment)"
        record_phase "1. Labels" "fail"
        return 1
        ;;
    esac

    declared_names="${declared_names}${name}
"
    run_or_dry gh label create "$name" --color "$color" --description "$description" --repo "$REPO" --force \
      || { fail "gh label create failed for '${name}'"; record_phase "1. Labels" "fail"; return 1; }
    ok "label: $name"
  done <<EOF
$parsed
EOF

  # Find repo labels not declared in labels.yml (prune candidates).
  #
  # Tool-managed labels: exclude anything matching `autorelease:*` from
  # pruning. These are release-please's own PR-state labels (e.g.
  # `autorelease: pending`, `autorelease: tagged`) — release-please creates
  # and manages them itself as part of its release-PR lifecycle, they are
  # never declared in .github/labels.yml, and deleting them breaks
  # release-please's state tracking. A live dogfood run pruned
  # `autorelease: pending` here and it had to be recreated; without this
  # exclusion, every bootstrap re-run would delete it again.
  local existing_names extra_names skipped_managed
  existing_names="$(gh label list --repo "$REPO" --limit 200 --json name -q '.[].name' 2>/dev/null || true)"
  extra_names=""
  skipped_managed=""
  if [ -n "$existing_names" ]; then
    while IFS= read -r existing; do
      [ -n "$existing" ] || continue
      if ! printf '%s\n' "$declared_names" | grep -qxF "$existing"; then
        case "$existing" in
          autorelease:*)
            skipped_managed="${skipped_managed}${existing}
"
            ;;
          *)
            extra_names="${extra_names}${existing}
"
            ;;
        esac
      fi
    done <<EOF
$existing_names
EOF
  fi

  if [ -n "$skipped_managed" ]; then
    printf '%s\n' "$skipped_managed" | sed '/^$/d' | while IFS= read -r managed; do
      skip "prune candidate '${managed}' (tool-managed)"
    done
  fi

  if [ -n "$extra_names" ]; then
    printf '\nLabels present on the repo but not declared in %s:\n' "$labels_file"
    printf '%s\n' "$extra_names" | sed '/^$/d' | sed 's/^/  - /'
    echo "(GitHub's default labels are noise under this taxonomy — pruning is the default.)"

    local do_prune=1
    if [ "$PRUNE_LABELS" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
      if ! confirm "Delete these labels?" "y"; then
        do_prune=0
      fi
    fi

    local prune_had_failure=0
    if [ "$do_prune" -eq 1 ]; then
      while IFS= read -r extra; do
        [ -n "$extra" ] || continue
        if run_or_dry gh label delete "$extra" --repo "$REPO" --yes; then
          ok "pruned label: $extra"
        else
          fail "gh label delete failed for '${extra}'"
          prune_had_failure=1
        fi
      done <<EOF
$extra_names
EOF
    else
      skip "label pruning (kept extra labels)"
    fi
    if [ "$prune_had_failure" -eq 1 ]; then
      record_phase "1. Labels" "fail"
      return 1
    fi
  else
    ok "no undeclared labels found"
  fi

  record_phase "1. Labels" "ok"
}

# --- Phase 2 — Issue types ---

# True when the coarse-Type label fallback is active. Reads the DECLARED set
# from labels.yml rather than querying the live repo: phase 1 has already synced
# the declaration to GitHub, and reading the file keeps --dry-run honest -- a dry
# run creates nothing, so a live-repo query would report "no fallback" on a repo
# that is about to get one.
# Echoes: none | partial | both. Checking only type:bug would misreport a
# half-uncommented pair in BOTH directions -- a repo with only type:feature
# would pass the org single-home check silently, and a repo with only type:bug
# would be told both labels are in use.
#
# Reads the DECLARED set from labels.yml rather than querying the live repo:
# phase 1 has already synced the declaration, and reading the file keeps
# --dry-run honest (a dry run creates nothing, so a live query would report "no
# fallback" for a repo that is about to get one).
coarse_type_fallback_state() {
  local labels_file=".github/labels.yml" declared bug=0 feature=0
  if [ ! -f "$labels_file" ]; then
    printf 'none'
    return 0
  fi
  declared="$(parse_labels_yml "$labels_file" | cut -f1)"
  if printf '%s\n' "$declared" | grep -qxF "type:bug"; then bug=1; fi
  if printf '%s\n' "$declared" | grep -qxF "type:feature"; then feature=1; fi
  if [ "$bug" -eq 1 ] && [ "$feature" -eq 1 ]; then
    printf 'both'
  elif [ "$bug" -eq 1 ] || [ "$feature" -eq 1 ]; then
    printf 'partial'
  else
    printf 'none'
  fi
}

phase_issue_types() {
  doing "Phase 2: native issue types"

  # Check the gh exit code explicitly instead of relying on stdout
  # emptiness: on an HTTP error (e.g. the guaranteed 404 on personal-account
  # repos) `gh api` prints the raw JSON error body to STDOUT — only the
  # one-line summary goes to stderr — so a plain `2>/dev/null || true`
  # capture would hold the error body as if it were data and never reach
  # the unavailable branch below.
  local types
  if ! types="$(gh api "repos/${REPO}/issue-types" --jq '.[].name' 2>/dev/null)"; then
    types=""
  fi

  if [ -z "$types" ]; then
    warn "repos/${REPO}/issue-types returned 404/empty"
    warn "native issue types are unavailable on this repo, so the issue forms' 'type:' key is silently ignored:"
    warn "  - org repo: enable/verify Bug/Feature/Task in Organization settings -> Repository -> Issue types"
    warn "  - personal account: GitHub rolled these out to user accounts too, so check Settings -> Issue types before assuming you cannot have them"
    warn "  see .github/PROJECT_FIELDS.md for the documented fallback on personal accounts"
    manual "Enable native issue types if you can — org repos in Organization settings, personal accounts in Settings → Issue types. If they are genuinely unavailable, see 'When native issue types are unavailable' in .github/PROJECT_FIELDS.md for the label fallback"
    case "$(coarse_type_fallback_state)" in
      both)
        ok "label fallback in use — coarse Type home is type:bug / type:feature (see .github/PROJECT_FIELDS.md)"
        ;;
      partial)
        warn "  label fallback is HALF declared — exactly one of type:bug / type:feature is uncommented in .github/labels.yml"
        warn "  the other coarse type has no home, so the pair is not a usable Type field"
        manual "Uncomment BOTH type:bug and type:feature in .github/labels.yml (or neither) and re-run bootstrap — a half-declared fallback leaves one coarse type homeless"
        ;;
      *)
        warn "  label fallback NOT in use — this repo currently has no home for coarse Type"
        manual "No coarse Type home. Either accept that (subtypes, priority and area still work), or uncomment the type:bug / type:feature block in .github/labels.yml and re-run bootstrap — see 'When native issue types are unavailable' in .github/PROJECT_FIELDS.md"
        ;;
    esac
    record_phase "2. Issue types" "warn"
    return
  fi

  local missing=""
  for t in Bug Feature Task; do
    if printf '%s\n' "$types" | grep -qxF "$t"; then
      ok "issue type present: $t"
    else
      missing="${missing}${t} "
    fi
  done

  # Enforcement in the other direction: native types are available here, so a
  # declared label fallback would give coarse Type two homes (ADR-0003). This is
  # the half a "ship them active" design cannot provide at all.
  local violation=0
  if [ "$(coarse_type_fallback_state)" != "none" ]; then
    violation=1
    warn "single-home violation: native issue types are available AND the type:bug/type:feature fallback is declared in .github/labels.yml"
    warn "  coarse Type now has two homes; they will drift (ADR-0003)"
    manual "Re-comment or delete the type:bug / type:feature entries in .github/labels.yml and re-run bootstrap — with native issue types available, the native type is the single home for coarse Type"
  fi

  if [ -n "$missing" ]; then
    warn "missing native issue type(s): $missing"
    manual "Add missing native issue type(s) in org/repo settings: $missing"
  fi

  if [ -n "$missing" ] || [ "$violation" -eq 1 ]; then
    record_phase "2. Issue types" "warn"
  else
    record_phase "2. Issue types" "ok"
  fi
}

# --- Phase 3 — Milestone ---

phase_milestone() {
  doing "Phase 3: v0.1.0 milestone"

  # state=all: milestones default to state=open-only on this endpoint, which
  # would miss a closed v0.1.0 and attempt to recreate it.
  # Exit code checked explicitly: on HTTP errors `gh api` prints the JSON
  # error body to stdout, so `|| true` would leave error text in $existing
  # (same failure mode as phase 2's issue-types check).
  local existing
  if ! existing="$(gh api "repos/${REPO}/milestones?state=all" --jq '.[].title' 2>/dev/null)"; then
    existing=""
  fi

  if printf '%s\n' "$existing" | grep -qxF "v0.1.0"; then
    ok "milestone v0.1.0 already exists"
    record_phase "3. Milestone" "ok"
    return
  fi

  local do_create=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    if ! confirm "Create milestone v0.1.0 ('First release')?" "y"; then
      do_create=0
    fi
  fi

  if [ "$do_create" -eq 1 ]; then
    run_or_dry gh api -X POST "repos/${REPO}/milestones" \
      -f title="v0.1.0" \
      -f description="First release" \
      || { fail "gh api milestone create failed"; record_phase "3. Milestone" "fail"; return 1; }
    ok "milestone v0.1.0 created"
    record_phase "3. Milestone" "ok"
  else
    skip "milestone creation"
    record_phase "3. Milestone" "skip"
  fi
}

# --- Phase 4 — Project ---

# Target Status options for a fresh project (single-home contract —
# .github/PROJECT_FIELDS.md). Order matters: it's compared positionally
# against both the live field and the pristine-default set below.
STATUS_TARGET_OPTIONS='Backlog
Ready
In Progress
In Review
Blocked
Done'

# GitHub's out-of-the-box Status options on a brand-new Project v2 board.
# Only a field still holding exactly this set is safe to overwrite
# automatically — anything else means a human already customized it.
STATUS_DEFAULT_OPTIONS='Todo
In Progress
Done'

# options_match <a> <b> — true if two newline-delimited option lists are
# identical, including order. Pure string comparison, no gh/network calls,
# so this is unit-testable in isolation (see the harness invoked from the
# validation step for this change).
options_match() {
  [ "$1" = "$2" ]
}

# status_options_decision <project_already_existed: 0|1> <current_options>
# — prints the action phase_project must take for the Status field:
#   target-skip        options already equal the target set (idempotent)
#   rewrite            project was created by THIS bootstrap run and still
#                      holds the pristine defaults — the only state safe to
#                      auto-rewrite (a just-created board cannot have items)
#   preexisting-manual project pre-existed this run: never auto-rewrite,
#                      even when its options look like the pristine
#                      defaults — it may already carry items whose Status
#                      values a rewrite would orphan (options get new IDs)
#   custom-manual      options are neither target nor defaults — a human
#                      customized them; hands off
# Pure string logic, no gh/network calls — unit-testable in isolation.
status_options_decision() {
  local already_existed="$1" opts="$2"
  if options_match "$opts" "$STATUS_TARGET_OPTIONS"; then
    printf 'target-skip'
  elif ! options_match "$opts" "$STATUS_DEFAULT_OPTIONS"; then
    printf 'custom-manual'
  elif [ "$already_existed" -eq 0 ]; then
    printf 'rewrite'
  else
    printf 'preexisting-manual'
  fi
}

phase_project() {
  if [ "$SKIP_PROJECT" -eq 1 ]; then
    skip "Phase 4: Project (--skip-project)"
    record_phase "4. Project" "skip"
    return
  fi

  doing "Phase 4: GitHub Project"

  local title="${REPO_NAME} board"
  local existing_titles
  existing_titles="$(gh project list --owner "$OWNER" --format json --jq '.projects[].title' 2>/dev/null || true)"

  local project_already_existed=0
  local project_number=""
  if printf '%s\n' "$existing_titles" | grep -qxF "$title"; then
    ok "project '${title}' already exists"
    project_already_existed=1
    project_number="$(gh project list --owner "$OWNER" --format json --jq ".projects[] | select(.title==\"${title}\") | .number" 2>/dev/null | head -n1 || true)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    run_or_dry gh project create --owner "$OWNER" --title "$title" \
      || { fail "gh project create failed"; record_phase "4. Project" "fail"; return 1; }
    project_number="DRY-RUN"
    ok "project '${title}' created"
  else
    local created_json
    created_json="$(gh project create --owner "$OWNER" --title "$title" --format json)" \
      || { fail "gh project create failed"; record_phase "4. Project" "fail"; return 1; }
    project_number="$(printf '%s' "$created_json" | grep -o '"number":[0-9]*' | head -n1 | cut -d: -f2)"
    ok "project '${title}' created"
  fi

  if [ -z "$project_number" ]; then
    warn "could not determine project number — skipping link/field-create steps"
    manual "Link the '${title}' project to ${REPO} and add the Effort field manually"
    record_phase "4. Project" "warn"
    return
  fi

  # gh project link errors if the project is already linked to this repo —
  # that's a successful/idempotent outcome on re-run, not a failure. Only a
  # freshly-created project needs an unconditional link attempt guarded the
  # same way (an already-existing project may already be linked).
  local link_output link_status=0
  link_output="$(run_or_dry gh project link "$project_number" --owner "$OWNER" --repo "$REPO" 2>&1)" || link_status=$?
  if [ "$link_status" -eq 0 ]; then
    printf '%s\n' "$link_output"
    ok "project linked to ${REPO}"
  elif printf '%s' "$link_output" | grep -qi "already linked"; then
    ok "project already linked to ${REPO}"
  else
    printf '%s\n' "$link_output" >&2
    fail "gh project link failed"
    record_phase "4. Project" "fail"
    return 1
  fi

  # Skip field-create when an "Effort" field already exists (re-run safety —
  # gh project field-create has no --force/upsert and would create a
  # duplicate field on every re-run otherwise).
  local existing_fields
  existing_fields="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[].name' 2>/dev/null || true)"
  if printf '%s\n' "$existing_fields" | grep -qxF "Effort"; then
    ok "Effort field already exists — skip create"
  elif [ "$project_already_existed" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ -z "$existing_fields" ]; then
    # field-list came back empty/unreadable for a pre-existing project —
    # do not risk a duplicate field; require a manual check instead.
    warn "could not list fields for existing project '${title}' — skipping Effort field-create to avoid a duplicate"
    manual "Verify the 'Effort' single-select field (S/M/L) exists on project '${title}'; add it manually if missing"
  else
    run_or_dry gh project field-create "$project_number" --owner "$OWNER" \
      --name "Effort" --data-type "SINGLE_SELECT" \
      --single-select-options "S,M,L" \
      || { fail "gh project field-create failed"; record_phase "4. Project" "fail"; return 1; }
    ok "Effort field created (S/M/L)"
  fi

  # Status options — set the single-home contract's target set
  # (Backlog/Ready/In Progress/In Review/Blocked/Done) via
  # updateProjectV2Field(singleSelectOptions:...). Auto-rewrite is only
  # safe on a project THIS run just created (still on pristine defaults,
  # guaranteed item-free): rewriting options assigns new option IDs, so on
  # any pre-existing project — even one whose options happen to look like
  # the untouched defaults — it could silently orphan the Status values of
  # items already on the board. Everything except the just-created case is
  # therefore skip (already target) or WARN + MANUAL (pre-existing or
  # customized). Decision logic lives in status_options_decision above.
  #
  # Skipped entirely for a project just created under --dry-run: its
  # "project_number" is the "DRY-RUN" placeholder (no real project exists
  # yet to query), matching the same fall-through the Effort field-create
  # step above relies on.
  if [ "$project_number" = "DRY-RUN" ]; then
    printf '%s[dry-run]%s would set Status options to the target set (Backlog/Ready/In Progress/In Review/Blocked/Done) on the newly created project\n' "$C_YELLOW" "$C_RESET"
  else
    local status_field_id status_options
    status_field_id="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[] | select(.name=="Status") | .id' 2>/dev/null || true)"

    if [ -z "$status_field_id" ]; then
      warn "could not determine the Status field id on project '${title}' — skipping Status options"
      manual "Verify the Status field on project '${title}' has options Backlog/Ready/In Progress/In Review/Blocked/Done; set them by hand if not — see docs/setup/project-views.md"
    else
      status_options="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[] | select(.name=="Status") | .options[].name' 2>/dev/null || true)"

      case "$(status_options_decision "$project_already_existed" "$status_options")" in
        target-skip)
          ok "Status options already match the target set — skip"
          ;;
        rewrite)
          # Single-quoted on purpose: $fieldId inside is a GraphQL variable
          # reference for gh to substitute via -f fieldId=..., not a shell
          # variable to expand here.
          # shellcheck disable=SC2016
          run_or_dry gh api graphql -f query='
            mutation($fieldId: ID!) {
              updateProjectV2Field(input: {
                fieldId: $fieldId,
                singleSelectOptions: [
                  {name: "Backlog", color: GRAY, description: "Not committed yet"},
                  {name: "Ready", color: GREEN, description: "Scoped and claimable (agent-ok issues are self-service here)"},
                  {name: "In Progress", color: YELLOW, description: "Being worked"},
                  {name: "In Review", color: ORANGE, description: "PR open, awaiting review"},
                  {name: "Blocked", color: RED, description: "Waiting on dependency or decision"},
                  {name: "Done", color: PURPLE, description: "Merged / completed"}
                ]
              }) {
                projectV2Field {
                  ... on ProjectV2SingleSelectField { id }
                }
              }
            }' -f fieldId="$status_field_id" \
            || { fail "gh api graphql updateProjectV2Field failed"; record_phase "4. Project" "fail"; return 1; }
          ok "Status options set to Backlog/Ready/In Progress/In Review/Blocked/Done"
          ;;
        preexisting-manual)
          warn "project '${title}' pre-existed this run — not rewriting its Status options (items may already reference them)"
          manual "Project '${title}' pre-existed bootstrap — set its Status options to Backlog/Ready/In Progress/In Review/Blocked/Done by hand (see docs/setup/project-views.md)"
          ;;
        *)
          warn "Status field on project '${title}' has custom options — not overwriting"
          manual "Project '${title}' Status field has non-default options — edit it by hand to Backlog/Ready/In Progress/In Review/Blocked/Done (see docs/setup/project-views.md) if that's what you want"
          ;;
      esac
    fi
  fi

  manual "GitHub's API cannot create views — follow docs/setup/project-views.md for the 3 views"

  record_phase "4. Project" "ok"
}

# --- Phase 5 — Repo settings ---

phase_repo_settings() {
  doing "Phase 5: repo settings"

  # Squash is the ONLY merge strategy. AGENTS.md ("squash merge; the PR title
  # becomes the commit message on main"), CONTRIBUTING.md, pr-authoring and
  # branch-and-commit all declare it; these settings make the buttons match the
  # docs. Rebase is off because nothing needs it: the release PR is merged by a
  # human like any other PR (ADR-0002 -- never auto-merge), not by
  # release-please, and release-please recommends squash-merge for the linear
  # history it parses.
  #
  # squash_merge_commit_title=PR_TITLE: GitHub's default is COMMIT_OR_PR_TITLE,
  # which silently uses the branch commit's subject whenever a PR has exactly
  # one commit -- making the documented claim above untrue for most PRs.
  #
  # squash_merge_commit_message=PR_BODY: GitHub's default concatenates every
  # branch commit message into the main commit body, and release-please
  # deliberately parses that body for additional Conventional Commits and
  # BREAKING-CHANGE footers. A WIP `feat:`/`fix:` commit on a branch would
  # become a phantom changelog entry or an unintended version bump. Not
  # hypothetical: `chore: release 0.2.0 (#7)` on this repo's main carries
  # `* chore: trigger CI on release PR` in its body -- harmless only because
  # `chore` is release-please's hidden bucket.
  #
  # allow_update_branch=true: the ruleset sets
  # strict_required_status_checks_policy=false, so the "Update branch" button is
  # not offered at all without this. Its merge commits are squashed away.
  #
  # wiki off = docs live in-repo.
  run_or_dry gh api -X PATCH "repos/${REPO}" \
    -F allow_squash_merge=true \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=false \
    -f squash_merge_commit_title=PR_TITLE \
    -f squash_merge_commit_message=PR_BODY \
    -F allow_update_branch=true \
    -F delete_branch_on_merge=true \
    -F has_issues=true \
    -F has_wiki=false \
    || { fail "gh api repo settings PATCH failed"; record_phase "5. Repo settings" "fail"; return 1; }

  ok "merge strategy: squash only (merge commits and rebase disabled)"
  ok "squash commit message: PR title + PR body"
  ok "delete_branch_on_merge=true, allow_update_branch=true, has_issues=true, has_wiki=false"

  record_phase "5. Repo settings" "ok"
}

# --- Phase 6 — Security ---

# Read-mostly by design, and the write path is bounded by COST, not by
# capability: the only settings this phase ever enables are free by
# construction. Anything with a billing consequence is reported and handed to
# the operator as a MANUAL step.
#
# Secret scanning is therefore offered only on a PUBLIC repo, where it is free.
# On a private or internal repo it needs a paid GitHub Advanced Security /
# Secret Protection seat, so this phase reports and stops rather than creating a
# per-committer billing obligation on the adopter's account. Dependabot alerts
# and automated security fixes are free everywhere, so they are offered on any
# visibility -- and .github/dependabot.yml already asserts both are on, with
# nothing until now verifying it.
#
# This phase NEVER changes repository visibility, and must not learn to. Private
# -> public erases stars and watchers and publishes all Actions history; that is
# a one-way door, not a bootstrap decision. Detection only.
#
# Unlike phases 3/5/8, this phase runs several independent checks, so it
# accumulates $result and calls record_phase ONCE at the end (the pattern
# phase_issue_types uses) -- run_phase's contract wants exactly one record per
# exit path, not one per check.
phase_security() {
  doing "Phase 6: security settings"

  local result="ok"

  # One read, three facts. security_and_analysis is only populated for callers
  # with admin permission on the repo -- it comes back null otherwise -- so the
  # "unknown" fallbacks below mean "could not read", never "disabled".
  # Exit code checked explicitly: on HTTP errors `gh api` prints the JSON error
  # body to stdout (same failure mode as phase 2's issue-types check).
  local facts
  if ! facts="$(gh api "repos/${REPO}" --jq '[.visibility, (.security_and_analysis.secret_scanning.status // "unknown"), (.security_and_analysis.secret_scanning_push_protection.status // "unknown")] | @tsv' 2>/dev/null)"; then
    facts=""
  fi

  if [ -z "$facts" ]; then
    warn "could not read repos/${REPO} security settings — the token may lack admin on this repo"
    manual "Review Settings → Advanced Security by hand: secret scanning, push protection, Dependabot alerts, Dependabot security updates"
    record_phase "6. Security" "warn"
    return
  fi

  local visibility secret_scanning push_protection
  visibility="$(printf '%s' "$facts" | cut -f1)"
  secret_scanning="$(printf '%s' "$facts" | cut -f2)"
  push_protection="$(printf '%s' "$facts" | cut -f3)"
  ok "repository visibility: ${visibility}"

  if [ "$visibility" = "public" ]; then
    if [ "$secret_scanning" = "unknown" ] || [ "$push_protection" = "unknown" ]; then
      # security_and_analysis is only populated for callers with admin on the
      # repo. "unknown" therefore means COULD NOT READ, never "disabled" --
      # prompting here (or PATCHing under --yes) would act on a guess, and the
      # phase would report a state it never actually observed.
      warn "cannot read secret scanning state (secret scanning: ${secret_scanning}, push protection: ${push_protection})"
      warn "  security_and_analysis is only visible to callers with admin on ${REPO}"
      warn "  this is 'not readable', not 'disabled' — bootstrap will not guess"
      manual "Check Settings → Advanced Security → Secret scanning and Push protection by hand; bootstrap could not read their current state"
      result="warn"
    elif [ "$secret_scanning" = "enabled" ] && [ "$push_protection" = "enabled" ]; then
      ok "secret scanning + push protection: already enabled"
    else
      cat <<'EOF'
Secret scanning and push protection are free on public repositories. Scanning
finds credentials already committed; push protection blocks a push that would
add a new one. Neither is switched on by converting a repo from private to
public — push protection in particular has to be enabled explicitly.
EOF
      if confirm "Enable secret scanning and push protection on ${REPO}?" "y"; then
        # security_and_analysis is a nested object. gh's key[subkey]=value
        # syntax builds it, which keeps the whole call inside run_or_dry and
        # visible under --dry-run instead of needing a piped JSON body.
        if run_or_dry gh api -X PATCH "repos/${REPO}" \
          -f 'security_and_analysis[secret_scanning][status]=enabled' \
          -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'; then
          ok "secret scanning + push protection enabled"
        else
          warn "secret scanning PATCH failed — needs admin on ${REPO}"
          manual "Enable Settings → Advanced Security → Secret scanning and Push protection"
          result="warn"
        fi
      else
        skip "secret scanning + push protection (both free on this public repo)"
        manual "Enable Settings → Advanced Security → Secret scanning and Push protection"
        result="warn"
      fi
    fi
  else
    warn "repository is ${visibility}: secret scanning (${secret_scanning}), push protection (${push_protection})"
    warn "  on a private/internal repo these need a paid GitHub Advanced Security / Secret Protection seat"
    warn "  bootstrap will not enable them for you — that is a billing decision, not a setup step"
    manual "Private repo: decide whether to license GitHub Secret Protection, then enable secret scanning + push protection in Settings → Advanced Security"
    result="warn"
  fi

  # GET returns 204 when enabled and 404 when not, so the exit code IS the
  # answer -- but a 403 (a token without admin) also exits non-zero, so the
  # wording covers "or not visible" rather than asserting the wrong one.
  if gh api "repos/${REPO}/vulnerability-alerts" >/dev/null 2>&1; then
    ok "Dependabot alerts: enabled"
  elif confirm "Enable Dependabot alerts? (free on every plan; .github/dependabot.yml assumes it)" "y"; then
    if run_or_dry gh api -X PUT "repos/${REPO}/vulnerability-alerts"; then
      ok "Dependabot alerts enabled"
    else
      warn "could not enable Dependabot alerts — needs admin on ${REPO}, or they are not visible to this token"
      manual "Enable Settings → Advanced Security → Dependabot alerts"
      result="warn"
    fi
  else
    skip "Dependabot alerts"
    manual "Enable Settings → Advanced Security → Dependabot alerts (.github/dependabot.yml assumes it is on)"
    result="warn"
  fi

  # {"enabled":bool,"paused":bool}. Enabled-but-paused is a real state and must
  # not be reported as plain "enabled" — paused means no fix PRs ever open.
  local fixes_facts fixes paused
  if ! fixes_facts="$(gh api "repos/${REPO}/automated-security-fixes" --jq '[.enabled, .paused] | @tsv' 2>/dev/null)"; then
    fixes_facts=""
  fi
  fixes="$(printf '%s' "$fixes_facts" | cut -f1)"
  paused="$(printf '%s' "$fixes_facts" | cut -f2)"

  if [ "$fixes" = "true" ] && [ "$paused" = "true" ]; then
    warn "Dependabot security updates: enabled but PAUSED — no automatic fix PRs will open"
    manual "Un-pause Dependabot security updates in Settings → Advanced Security"
    result="warn"
  elif [ "$fixes" = "true" ]; then
    ok "Dependabot security updates: enabled"
  elif confirm "Enable Dependabot security updates (automated security fixes)?" "y"; then
    if run_or_dry gh api -X PUT "repos/${REPO}/automated-security-fixes"; then
      ok "Dependabot security updates enabled"
    else
      warn "could not enable Dependabot security updates — needs admin, and Dependabot alerts must be on first"
      manual "Enable Settings → Advanced Security → Dependabot security updates"
      result="warn"
    fi
  else
    skip "Dependabot security updates"
    manual "Enable Settings → Advanced Security → Dependabot security updates"
    result="warn"
  fi

  record_phase "6. Security" "$result"
}

# --- Phase 7 — Actions PR permission ---

phase_actions_permission() {
  doing "Phase 7: Actions PR creation/approval permission"

  cat <<'EOF'
release-please opens and updates its own release PR from a workflow run. By
default GitHub Actions cannot create or approve pull requests, which makes
release-please fail with:
  "GitHub Actions is not permitted to create or approve pull requests"
EOF

  local do_enable=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    if ! confirm "Enable 'Actions can create and approve pull requests'?" "y"; then
      do_enable=0
    fi
  fi

  if [ "$do_enable" -eq 1 ]; then
    run_or_dry gh api -X PUT "repos/${REPO}/actions/permissions/workflow" \
      -f default_workflow_permissions=read \
      -F can_approve_pull_request_reviews=true \
      || { fail "gh api Actions permissions PUT failed"; record_phase "7. Actions permission" "fail"; return 1; }
    ok "Actions can now create and approve pull requests"
    record_phase "7. Actions permission" "ok"
  else
    skip "Actions PR permission (release-please will fail until this is enabled)"
    manual "Enable Settings → Actions → General → 'Allow GitHub Actions to create and approve pull requests', or release-please will fail"
    record_phase "7. Actions permission" "skip"
  fi
}

# --- Phase 8 — Ruleset ---

phase_ruleset() {
  doing "Phase 8: branch ruleset"

  local ruleset_file=".github/rulesets/main-branch.json"
  if [ ! -f "$ruleset_file" ]; then
    warn "no ${ruleset_file} found — skipping ruleset import"
    record_phase "8. Ruleset" "skip"
    return
  fi

  # Exit code checked explicitly: on HTTP errors `gh api` prints the JSON
  # error body to stdout, so `|| true` would leave error text in $existing
  # (same failure mode as phase 2's issue-types check).
  local existing
  if ! existing="$(gh api "repos/${REPO}/rulesets" --jq '.[].name' 2>/dev/null)"; then
    existing=""
  fi

  if printf '%s\n' "$existing" | grep -qxF "main-branch-protection"; then
    ok "ruleset 'main-branch-protection' already exists — rulesets are create-once, this run will NOT sync changes; delete it on GitHub (Settings → Rules → Rulesets) and re-run to update"
    record_phase "8. Ruleset" "skip"
    return
  fi

  run_or_dry gh api -X POST "repos/${REPO}/rulesets" --input "$ruleset_file" \
    || { fail "gh api ruleset POST failed"; record_phase "8. Ruleset" "fail"; return 1; }
  ok "ruleset 'main-branch-protection' created"
  record_phase "8. Ruleset" "ok"
}

# --- Phase 9 — Licence ---

# Identity of the TEMPLATE this repository was created from. These must match
# LICENSE; scripts/check-license-marker.sh asserts the first two on every
# `make check`. Anyone forking this template into a template of their own MUST
# update them together -- if they drift, phase 9 stops recognising its own
# licence and silently does nothing, which is the exact defect it exists to
# prevent.
TEMPLATE_COPYRIGHT_HOLDER="TzuH-Hsu"
TEMPLATE_COPYRIGHT_YEAR="2026"
TEMPLATE_NAME="GitHub Project OS"
TEMPLATE_URL="https://github.com/TzuH-Hsu/github-project-os"

# __YEAR__ / __HOLDER__ are substituted with bash parameter expansion, NOT sed:
# holder names legitimately contain & and /, both sed replacement
# metacharacters. The MIT body lives here exactly once and is reused for both
# the adopter's LICENSE (answer 1) and the upstream attribution in NOTICE
# (every writing answer).
LICENSE_MIT_SEED='MIT License

Copyright (c) __YEAR__ __HOLDER__

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'

# Deliberately NOT shipped as docs/template/LICENSE.proprietary.example: under
# --yes this phase writes nothing and files a manual step, and phase 10 then
# removes docs/template/ -- deleting the example in the very run that told the
# adopter to go read it. It is reproduced in docs/setup/licensing.md, which
# survives de-templating.
LICENSE_PROPRIETARY_SEED='PROPRIETARY SOFTWARE -- ALL RIGHTS RESERVED

Copyright (c) __YEAR__ __HOLDER__. All rights reserved.

1. No licence granted

   This repository and its contents (the "Work") are proprietary and
   confidential. No licence, express or implied, is granted by this file. You
   may not use, copy, modify, merge, publish, distribute, sublicense, sell, or
   create derivative works of the Work, in whole or in part, except under a
   separate written agreement signed by the copyright holder named above.

2. Commissioned work

   If the Work was produced under a commission, services, or work-for-hire
   agreement, that agreement -- not this file -- determines who owns the Work
   and when ownership or a licence passes to the commissioning party (commonly
   on final payment). Until the conditions of that agreement are met, all
   rights remain with the copyright holder named above. This file does not
   transfer, assign, or waive anything, and it does not modify that agreement.

3. Third-party components

   The scaffolding in this repository derives from third-party open-source
   software, which remains under its own licence. See the NOTICE file.
   Sections 1 and 2 do not apply to those components, and nothing in NOTICE
   grants any right in the rest of the Work.

4. No warranty

   THE WORK IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW.

--------------------------------------------------------------------------
Template-generated example -- NOT LEGAL ADVICE.

This file was written into your repository by scripts/bootstrap.sh from a
generic example shipped with a project template. It has not been reviewed by a
lawyer, it is not tailored to your jurisdiction, your business, or your
contract, and a notice file cannot override, replace, or complete the terms of
a signed agreement. Have your own counsel review it. Once they have, delete
this trailer.
--------------------------------------------------------------------------
'

# subst_all <haystack> <needle> <replacement> -- literal, no pattern semantics.
#
# ${var//needle/repl} is NOT usable here. With patsub_replacement (on by
# default in bash 5.2+) an unescaped `&` in the REPLACEMENT expands to the
# matched text, so a holder like "Smith & Jones" renders as
# "Smith __HOLDER__ Jones" -- silently corrupting the copyright line of a
# LICENSE file. Escaping it as \& is itself literal on bash 3.2 (macOS
# /bin/bash), so no single expansion is correct on both. Prefix/suffix removal
# never interprets the replacement at all, on any version.
#
# Callers use $(subst_all ...), and command substitution strips ALL trailing
# newlines -- so a caller writing the result to a file must re-add one
# (printf '%s\\n'), and callers concatenating must not rely on the seed's
# trailing newline surviving.
subst_all() {
  local haystack="$1" needle="$2" repl="$3" out="" head
  while [ -n "$haystack" ]; do
    case "$haystack" in
      *"$needle"*)
        head="${haystack%%"$needle"*}"
        out="${out}${head}${repl}"
        haystack="${haystack#*"$needle"}"
        ;;
      *)
        out="${out}${haystack}"
        haystack=""
        ;;
    esac
  done
  printf '%s' "$out"
}

license_explain() {
  cat <<'EOF'

This repository still carries the TEMPLATE's licence: MIT, copyright the
template author. That is almost certainly not what you want.

  - MIT is an irrevocable grant. Anyone who obtains a copy may use, modify,
    publish, distribute, sublicense and SELL it. Publishing it once cannot be
    undone.
  - For client or commissioned work this is usually wrong, and can conflict
    with your contract: a commission agreement normally transfers copyright on
    final payment, while an MIT file in the delivered repo grants the client
    (and everyone else) far more than that -- before you have been paid.
  - Even if you do want MIT, the copyright line must name YOU, not the
    template author.

  1) MIT, under your name
     Keeps the MIT terms, rewrites the copyright line to you.
  2) Proprietary / all rights reserved
     For client, commissioned and closed-source work. Replaces LICENSE with an
     all-rights-reserved notice that defers to your commission agreement.
  3) Decide later
     Leaves LICENSE untouched (still the template author's MIT) and puts this
     at the TOP of the remaining manual steps.

Choosing something else entirely (Apache-2.0, GPL, BUSL...) is answer 3: pick
the text yourself. This script ships no other licence bodies.

Either way, a NOTICE file records that this repository's scaffolding derives
from the template under the MIT licence. That attribution must be kept even if
you relicense -- see docs/setup/licensing.md.
EOF
}

# Sets LICENSE_CHOICE to mit|proprietary|defer. Deliberately has NO default: a
# bare Enter re-asks. confirm() treats a closed stdin as "take the default",
# which here would mean silently shipping the template author's MIT -- the
# original bug with extra steps. A closed stdin, or three unusable answers,
# resolves to defer, and defer never writes.
prompt_license_choice() {
  local reply attempts=0
  while [ "$attempts" -lt 3 ]; do
    attempts=$((attempts + 1))
    printf '\nChoose 1, 2 or 3: '
    if ! read -r reply; then
      printf '\n'
      warn "stdin closed — deferring the licence decision"
      LICENSE_CHOICE="defer"
      return 0
    fi
    case "$reply" in
      1|mit|MIT)     LICENSE_CHOICE="mit";         return 0 ;;
      2|proprietary) LICENSE_CHOICE="proprietary"; return 0 ;;
      3|defer|later) LICENSE_CHOICE="defer";       return 0 ;;
      '') printf 'No default here — type 1, 2 or 3.\n' ;;
      *)  printf 'Please answer 1, 2 or 3.\n' ;;
    esac
  done
  warn "no valid answer after 3 attempts — deferring the licence decision"
  LICENSE_CHOICE="defer"
}

# Sets LICENSE_HOLDER. Preference: an interactive answer, then
# `git config user.name`, then the GitHub owner login. The login is a last
# resort and gets a WARN, because a handle is not the legal entity a copyright
# line should name (in this very repo the two differ).
prompt_license_holder() {
  local default_holder reply
  default_holder="$(git config user.name 2>/dev/null || true)"
  if [ -z "$default_holder" ]; then
    default_holder="$OWNER"
    warn "git config user.name is unset — defaulting to the repo owner login '${OWNER}'"
  fi

  if [ "$ASSUME_YES" -eq 1 ] || [ -n "$LICENSE_MODE" ]; then
    LICENSE_HOLDER="$default_holder"
    ok "copyright holder: ${LICENSE_HOLDER} (non-interactive)"
    manual "Confirm the copyright holder in LICENSE is your correct legal name or company — bootstrap used '${LICENSE_HOLDER}' without asking"
    return 0
  fi

  printf 'Copyright holder (your legal name or company) [%s]: ' "$default_holder"
  if ! read -r reply; then reply=""; printf '\n'; fi
  [ -n "$reply" ] || reply="$default_holder"
  LICENSE_HOLDER="$reply"
}

# NOTICE carries the TEMPLATE's MIT notice, which the adopter must retain even
# after relicensing -- rewriting LICENSE's copyright line would otherwise delete
# the only copy of it in the repository, which MIT forbids. Created only when
# absent: an adopter who has added their own third-party sections keeps them.
write_notice() {
  # File existence is NOT proof the template's notice is present: an adopter may
  # already keep a NOTICE for their own dependencies. Returning early there would
  # replace LICENSE while dropping the only copy of the upstream MIT notice --
  # exactly the violation this phase exists to prevent. Check for the notice
  # itself, and append rather than overwrite.
  local upstream_line="Copyright (c) ${TEMPLATE_COPYRIGHT_YEAR} ${TEMPLATE_COPYRIGHT_HOLDER}"
  local append=0
  if [ -f NOTICE ]; then
    if grep -qxF "$upstream_line" NOTICE; then
      ok "NOTICE already carries the ${TEMPLATE_NAME} attribution — leaving it alone"
      return 0
    fi
    append=1
    ok "NOTICE exists without the ${TEMPLATE_NAME} attribution — appending, keeping your content"
  fi

  local mit_upstream body
  mit_upstream="$(subst_all "$LICENSE_MIT_SEED" "__YEAR__" "$TEMPLATE_COPYRIGHT_YEAR")"
  mit_upstream="$(subst_all "$mit_upstream" "__HOLDER__" "$TEMPLATE_COPYRIGHT_HOLDER")"

  body="NOTICE — third-party attribution

This repository's scaffolding — the GitHub Actions workflows, issue and pull
request templates, Makefile, scripts/, skills/, and the docs/ structure —
derives from ${TEMPLATE_NAME} and is used under the MIT Licence.

The MIT Licence requires that its copyright notice and permission notice be
included in all copies or substantial portions of that software. They are
reproduced below for that purpose, and must be kept in this repository even if
the rest of it is relicensed.

The terms below apply ONLY to that scaffolding. They grant no rights in any
other part of this repository; see LICENSE for those.

--------------------------------------------------------------------------
${TEMPLATE_NAME} — ${TEMPLATE_URL}

${mit_upstream}
--------------------------------------------------------------------------
"

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$append" -eq 1 ]; then
      printf '%s[dry-run]%s would append the %s MIT attribution to the existing NOTICE\n' "$C_YELLOW" "$C_RESET" "$TEMPLATE_NAME"
    else
      printf '%s[dry-run]%s would create NOTICE (MIT attribution for %s)\n' "$C_YELLOW" "$C_RESET" "$TEMPLATE_NAME"
    fi
    return 0
  fi

  if [ "$append" -eq 1 ]; then
    printf '\n%s' "$body" >> NOTICE || { fail "appending to NOTICE failed"; return 1; }
    ok "NOTICE appended (MIT attribution for ${TEMPLATE_NAME}; existing content kept)"
  else
    printf '%s' "$body" > NOTICE || { fail "writing NOTICE failed"; return 1; }
    ok "NOTICE created (MIT attribution for ${TEMPLATE_NAME})"
  fi
}

phase_license() {
  doing "Phase 9: licence"

  if [ ! -f LICENSE ]; then
    warn "no LICENSE file in this repo"
    manual_urgent "This repository has no LICENSE. Add one before publishing it or delivering it to anyone — see docs/setup/licensing.md"
    record_phase "9. Licence" "warn"
    return
  fi

  # Guard exactly the paths this phase writes, same contract as phase 10's
  # guard and equally not bypassed by --yes. LICENSE must NOT be added to
  # phase 10's list: writing it here would dirty the worktree and make
  # de-template skip itself on every run.
  local dirty_paths
  dirty_paths="$(git status --porcelain -- LICENSE NOTICE 2>/dev/null || true)"
  if [ -n "$dirty_paths" ]; then
    warn "licence step skipped: LICENSE/NOTICE have uncommitted changes — commit or stash first"
    printf '%s\n' "$dirty_paths" | sed 's/^/  /'
    manual_urgent "Bootstrap did not touch LICENSE (uncommitted changes present). Confirm it names YOU, not the template author, before publishing or delivering this repository — docs/setup/licensing.md"
    record_phase "9. Licence" "skip"
    return
  fi

  # Fixed-string whole-line match avoids regex-escaping "(c)". A LICENSE that
  # no longer carries the template's line was already decided by the adopter.
  local template_line="Copyright (c) ${TEMPLATE_COPYRIGHT_YEAR} ${TEMPLATE_COPYRIGHT_HOLDER}"
  if ! grep -qxF "$template_line" LICENSE; then
    ok "LICENSE no longer carries the template's copyright line — leaving it alone"
    record_phase "9. Licence" "skip"
    return
  fi

  if [ -n "$LICENSE_MODE" ]; then
    LICENSE_CHOICE="$LICENSE_MODE"
    ok "licence choice from --license: ${LICENSE_CHOICE}"
  elif [ "$ASSUME_YES" -eq 1 ]; then
    LICENSE_CHOICE="defer"
  else
    license_explain
    prompt_license_choice
  fi

  if [ "$LICENSE_CHOICE" = "defer" ]; then
    skip "licence decision deferred — LICENSE still carries the template author's MIT"
    manual_urgent "LICENSE still carries the TEMPLATE author's MIT copyright. Decide your licence BEFORE publishing this repository or delivering it to a client — MIT under your own name, proprietary/all-rights-reserved, or another licence — and record the scaffolding attribution in NOTICE. Both files are ready to copy in docs/setup/licensing.md"
    record_phase "9. Licence" "warn"
    return
  fi

  prompt_license_holder

  local year rendered
  year="$(date +%Y)"
  case "$LICENSE_CHOICE" in
    mit)         rendered="$LICENSE_MIT_SEED" ;;
    proprietary) rendered="$LICENSE_PROPRIETARY_SEED" ;;
    *)           fail "unreachable licence choice '${LICENSE_CHOICE}'"; record_phase "9. Licence" "fail"; return 1 ;;
  esac
  rendered="$(subst_all "$rendered" "__YEAR__" "$year")"
  rendered="$(subst_all "$rendered" "__HOLDER__" "$LICENSE_HOLDER")"

  # A plain redirect, not run_or_dry: that helper is the choke point for
  # mutating `gh` calls, and the CHANGELOG/manifest writes in phase 10 branch
  # on DRY_RUN inline the same way.
  # NOTICE FIRST, deliberately. If the attribution cannot be written -- directory
  # permissions, quota, I/O -- LICENSE must be left exactly as it was. Writing
  # LICENSE first and failing here would leave the repository with neither the
  # template's original notice nor the promised attribution, which is a worse
  # state than not having run the phase at all.
  write_notice || { record_phase "9. Licence" "fail"; return 1; }

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s[dry-run]%s would write LICENSE (%s, copyright %s %s)\n' \
      "$C_YELLOW" "$C_RESET" "$LICENSE_CHOICE" "$year" "$LICENSE_HOLDER"
  else
    printf '%s\n' "$rendered" > LICENSE \
      || { fail "writing LICENSE failed"; record_phase "9. Licence" "fail"; return 1; }
  fi
  ok "LICENSE written (${LICENSE_CHOICE}, copyright ${year} ${LICENSE_HOLDER})"

  if [ "$LICENSE_CHOICE" = "proprietary" ]; then
    manual "Have counsel review LICENSE — it is a template-generated example — then delete the 'Template-generated example' trailer at the bottom of the file"
  fi
  if [ "$KEEP_TEMPLATE_DOCS" -eq 1 ] && [ "$LICENSE_CHOICE" != "mit" ]; then
    manual "README.md still shows the template's MIT badge and 'License: MIT' link (you kept it via --keep-template-docs) — update both to match your new LICENSE"
  fi

  record_phase "9. Licence" "ok"
}

# --- Phase 10 — De-template ---

CHANGELOG_SEED='# Changelog

All notable changes are recorded here by release-please (Conventional Commits
drive the entries — see docs/adr/ADR-0002-release-flow.md).

## Unreleased

No entries yet.
'

phase_detemplate() {
  if [ "$KEEP_TEMPLATE_DOCS" -eq 1 ]; then
    skip "Phase 10: de-template (--keep-template-docs)"
    record_phase "10. De-template" "skip"
    return
  fi

  doing "Phase 10: de-template"

  if [ ! -d "docs/template" ]; then
    ok "docs/template/ absent — repo is already de-templated, nothing to do"
    record_phase "10. De-template" "skip"
    return
  fi

  # Worktree guard: de-templating mutates/deletes README.md, CHANGELOG.md,
  # docs/template/, and .release-please-manifest.json with no undo. If any
  # of those paths already carry uncommitted changes, a failure partway
  # through (or just an unwanted mix of manual + generated edits) is
  # unrecoverable via git. Require a clean state on exactly these paths
  # before mutating anything — unconditionally, --yes does not bypass this.
  local dirty_paths
  dirty_paths="$(git status --porcelain -- README.md CHANGELOG.md docs/template .release-please-manifest.json 2>/dev/null || true)"
  if [ -n "$dirty_paths" ]; then
    warn "de-template skipped: affected paths have uncommitted changes — commit or stash first"
    printf '%s\n' "$dirty_paths" | sed 's/^/  /'
    record_phase "10. De-template" "skip"
    return
  fi

  local do_detemplate=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    cat <<'EOF'
This converts this repo from the template product to YOUR project:
  - docs/template/README.starter.md becomes README.md
  - docs/template/ is removed
  - CHANGELOG.md is reset to its 8-line seed
EOF
    if ! confirm "Proceed with de-templating?" "y"; then
      do_detemplate=0
    fi
  fi

  if [ "$do_detemplate" -eq 0 ]; then
    skip "de-templating"
    record_phase "10. De-template" "skip"
    return
  fi

  # The rm -rf below must be unreachable unless the mv is verifiably safe:
  # either there was no starter README to move (nothing to lose), or the mv
  # ran and left a verified README.md with the source gone. Never fall
  # through to deleting docs/template/ on an unverified/failed mv — that is
  # exactly the "README lost" failure mode this guard exists to prevent.
  local readme_source="docs/template/README.starter.md"
  local safe_to_remove_template=0
  if [ -f "$readme_source" ]; then
    if run_or_dry mv "$readme_source" README.md; then
      if [ "$DRY_RUN" -eq 1 ]; then
        # dry-run never actually moves the file; trust the no-op contract.
        safe_to_remove_template=1
        ok "[dry-run] README.md would be replaced with ${readme_source}"
      elif [ -f "README.md" ] && [ ! -f "$readme_source" ]; then
        safe_to_remove_template=1
        ok "README.md replaced with ${readme_source}"
      else
        fail "mv reported success but README.md / ${readme_source} state is not as expected — refusing to remove docs/template/"
        record_phase "10. De-template" "fail"
        return 1
      fi
    else
      fail "mv ${readme_source} README.md failed — refusing to remove docs/template/"
      record_phase "10. De-template" "fail"
      return 1
    fi
  else
    warn "${readme_source} not found — leaving README.md as-is"
    safe_to_remove_template=1
  fi

  if [ "$safe_to_remove_template" -ne 1 ]; then
    fail "de-template: mv step did not verify as safe — aborting before docs/template/ removal"
    record_phase "10. De-template" "fail"
    return 1
  fi

  run_or_dry rm -rf docs/template \
    || { fail "rm -rf docs/template failed"; record_phase "10. De-template" "fail"; return 1; }
  ok "docs/template/ removed"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s[dry-run]%s would reset CHANGELOG.md to its 8-line seed\n' "$C_YELLOW" "$C_RESET"
  else
    printf '%s' "$CHANGELOG_SEED" > CHANGELOG.md \
      || { fail "writing CHANGELOG.md failed"; record_phase "10. De-template" "fail"; return 1; }
  fi
  ok "CHANGELOG.md reset to seed"

  local manifest='.release-please-manifest.json'
  local want='{".":"0.0.0"}'
  local have=""
  if [ -f "$manifest" ]; then
    have="$(tr -d '[:space:]' < "$manifest")"
  fi
  if [ "$have" = "$want" ]; then
    ok "${manifest} already at {\".\": \"0.0.0\"}"
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s[dry-run]%s would rewrite %s to {".": "0.0.0"}\n' "$C_YELLOW" "$C_RESET" "$manifest"
    else
      printf '{\n  ".": "0.0.0"\n}\n' > "$manifest" \
        || { fail "writing ${manifest} failed"; record_phase "10. De-template" "fail"; return 1; }
    fi
    ok "${manifest} rewritten to {\".\": \"0.0.0\"}"
  fi

  cat <<'EOF'

Note: release-as: 0.1.0 stays in release-please-config.json — your first
release is v0.1.0; remove that key afterwards so subsequent releases
follow normal Conventional Commit bumps.
EOF
  manual "Remove the 'release-as: 0.1.0' key from release-please-config.json after your first release ships"

  record_phase "10. De-template" "ok"
}

# --- Summary ---

print_summary() {
  printf '\n%s=== Bootstrap summary ===%s\n\n' "$C_BOLD" "$C_RESET"

  # Walk parallel newline-delimited lists.
  local names_left="$PHASE_NAMES" results_left="$PHASE_RESULTS"
  local name result
  while [ -n "$names_left" ]; do
    name="${names_left%%$'\n'*}"
    names_left="${names_left#*$'\n'}"
    result="${results_left%%$'\n'*}"
    results_left="${results_left#*$'\n'}"
    [ -n "$name" ] || continue

    case "$result" in
      ok)   printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$name" ;;
      warn) printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      skip) printf '  %s-%s %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      *)    printf '  %sx%s %s\n' "$C_RED" "$C_RESET" "$name" ;;
    esac
  done

  if [ -n "$MANUAL_URGENT" ] || [ -n "$MANUAL_STEPS" ]; then
    printf '\n%sRemaining MANUAL steps:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s' "$MANUAL_URGENT" | sed '/^$/d' | sed 's/^- /  [ ] ! /'
    printf '%s' "$MANUAL_STEPS" | sed '/^$/d' | sed 's/^- /  [ ] /'
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n%sDry run only — zero mutations were executed.%s\n' "$C_YELLOW" "$C_RESET"
  else
    printf '\nBootstrap does not commit anything. Next steps:\n'
    printf '  1. Review: git status\n'
    printf '  2. Commit: git add -A && git commit -m "chore: bootstrap repository"\n'
  fi
  echo ""
}

# --- Main ---

# run_phase <phase-fn> <phase-label> — every phase_* function now guards
# and records its own result on every exit path (mutating commands are
# guarded explicitly with `|| { fail ...; record_phase ...; return 1; }`
# rather than relying on `set -e`, which is suspended for the duration of a
# function invoked as the left side of `||` — see phase function bodies).
# This wrapper is a defensive fallback ONLY: it records a "fail" for the
# phase label if — and only if — the phase function returned non-zero
# without recording anything itself (e.g. an unexpected/unguarded error).
# It never double-records a phase that already recorded its own result.
run_phase() {
  local phase_fn="$1" phase_label="$2"
  local names_before="$PHASE_NAMES"
  if ! "$phase_fn"; then
    if [ "$PHASE_NAMES" = "$names_before" ]; then
      fail "${phase_label}: exited non-zero without recording a result — treating as fail"
      record_phase "$phase_label" "fail"
    fi
  fi
}

main() {
  phase_preflight

  # Phases 1-10: failures are collected, not fatal — preflight is the only
  # phase whose failure aborts the whole run.
  run_phase phase_labels "1. Labels"
  run_phase phase_issue_types "2. Issue types"
  run_phase phase_milestone "3. Milestone"
  run_phase phase_project "4. Project"
  run_phase phase_repo_settings "5. Repo settings"
  run_phase phase_security "6. Security"
  run_phase phase_actions_permission "7. Actions permission"
  run_phase phase_ruleset "8. Ruleset"
  run_phase phase_license "9. Licence"
  run_phase phase_detemplate "10. De-template"

  print_summary
}

# Guarded so the file can be sourced to get its functions without running them.
# Nothing in `make verify` covers this script, so being able to exercise a
# single phase in isolation is the only unit-test surface it has.
# `bash scripts/bootstrap.sh` is unaffected.
if bootstrap_is_main; then
  main "$@"
fi
