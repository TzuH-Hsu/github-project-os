# Metadata single-home contract

Every issue/PR attribute lives in **exactly one place**. Never dual-write the same fact into a label *and* a Project field *and* a milestone — dual-homed metadata always drifts. This file is the authority map; if a tool or habit conflicts with it, this file wins (rationale: `docs/adr/ADR-0003-metadata-single-home.md`).

## Authority map

| Attribute | Home | Values / format |
| --- | --- | --- |
| Type (coarse) | **Native issue type** | `Bug` / `Feature` / `Task` — set by the issue form (no organization? see "Personal accounts") |
| Type (subtype) | `type:*` **labels** | `chore` / `ops` / `docs` / `security` — Task subtypes only |
| Priority | `priority:*` **labels** | `p0` critical / `p1` milestone-blocking / `p2` important / `p3` polish |
| Area | `area:*` **labels** | starter set: `docs`, `skills`, `ci`, `governance` — rename to your domains |
| Workflow status | **Project `Status` field** | `Backlog` / `Ready` / `In Progress` / `In Review` / `Blocked` / `Done` |
| Target version | **Milestone** | `vX.Y.Z` releases, `gov-*` process phases; **no milestone = backlog** |
| Effort | **Project `Effort` field** | `S` (≤ half a day) / `M` (≤ 2 days) / `L` (must be decomposed first) |
| Agent eligibility | `agent-ok` **label** | present = AI agents may self-serve when Status is `Ready` |
| Agent authorship | `by-agent` **label** | on PRs authored by an AI agent (audit trail) |
| Dependencies | **Native issue relationships** | GitHub blocked-by / blocking |
| Epic membership | **Native sub-issues** | parent issue with sub-issues; no `epic:*` labels |

## When native issue types are unavailable

Native issue types began as an organization-only feature and have since been
rolled out to personal accounts as well, so **check rather than assume**:

```bash
gh api repos/{owner}/{repo}/issue-types --jq '.[].name'
```

If that 404s or comes back empty, the issue forms' top-level `type:` key is
silently ignored — the form still captures intent at creation, but nothing
stores it. Bootstrap phase 2 runs this check for you and says which case you
are in.

The coarse Type row above therefore has **no home by default** on a personal
account. There are two supported resolutions, and you pick exactly one:

1. **Accept no coarse Type** (the default; nothing to configure). Task
   subtypes, priority, area, status and milestone all still work — you simply
   cannot filter by Bug vs Feature.
2. **Adopt the label fallback.** Uncomment the `type:bug` / `type:feature`
   block in `.github/labels.yml` and re-run `scripts/bootstrap.sh`. Labels
   become the *one* home for coarse Type, and the authority-map row above reads
   `type:bug` / `type:feature` **labels** instead of Native issue type.

This is still single-home, and it is enforced in both directions:

- The two labels ship **commented out**, never active, so an organization repo
  cannot end up holding a native `Bug` type *and* a `type:bug` label.
- Bootstrap phase 2 checks both directions. On a 404 it reports whether the
  fallback is in use; when native types *are* available and the fallback is
  also declared, it reports a single-home violation and tells you to re-comment
  the block.
- If you later transfer the repo into an organization, removing those two
  entries is part of enabling native types — not optional cleanup.
- The labels are applied **by hand**. `.github/workflows/issue-labeler.yml`
  never adds or removes them: the coarse Type comes from the form's top-level
  `type:` key, which is not part of the issue body the labeler parses.
- There is no `type:task`. An issue with neither label is a Task, and every
  Task already carries exactly one required
  `type:chore|ops|docs|security` subtype — so the Task query stays a single
  positive predicate rather than a negation.

## Rules

1. **One home per attribute.** Adding a Project field that mirrors a label (or vice versa) is a contract violation — remove one.
2. **Labels are for facts an agent can write in one `gh` call.** Workflow state belongs to the Project board, not labels.
3. **Milestone = commitment.** Assigning a milestone means "this ships in that version/phase". Backlog items carry no milestone.
4. **Retire, don't accumulate.** When a label or field stops earning its keep, delete it everywhere (see `skills/labels-and-taxonomy/`).

## Where things are defined

- Labels: `.github/labels.yml` (declarative source of truth; sync = re-run `scripts/bootstrap.sh`)
- Project fields: created by `scripts/bootstrap.sh`; views are set up manually — `docs/setup/project-views.md`
- Native issue types: set automatically by the issue forms in `.github/ISSUE_TEMPLATE/`
