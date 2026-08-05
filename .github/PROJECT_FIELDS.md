# Metadata single-home contract

Every issue/PR attribute lives in **exactly one place**. Never dual-write the same fact into a label *and* a Project field *and* a milestone — dual-homed metadata always drifts. This file is the authority map; if a tool or habit conflicts with it, this file wins (rationale: `docs/adr/ADR-0003-metadata-single-home.md`).

## Authority map

| Attribute | Home | Values / format |
| --- | --- | --- |
| Type (coarse) | **Native issue type** | `Bug` / `Feature` / `Task` — set by the issue form |
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

## Personal accounts

Native issue types require an organization — on personal-account repos the
coarse Type row above has no native home (`repos/{repo}/issue-types` 404s).
The issue form used at creation (bug/feature/task) still captures intent,
but GitHub silently ignores its `type:` key with no org to back it. Adopters
on personal accounts who need queryable coarse type may extend the `type:*`
labels with `bug`/`feature` as the Type home instead — this is still
single-home: labels become the *one* home for Type when native types are
unavailable, never both at once.

## Rules

1. **One home per attribute.** Adding a Project field that mirrors a label (or vice versa) is a contract violation — remove one.
2. **Labels are for facts an agent can write in one `gh` call.** Workflow state belongs to the Project board, not labels.
3. **Milestone = commitment.** Assigning a milestone means "this ships in that version/phase". Backlog items carry no milestone.
4. **Retire, don't accumulate.** When a label or field stops earning its keep, delete it everywhere (see `skills/labels-and-taxonomy/`).

## Where things are defined

- Labels: `.github/labels.yml` (declarative source of truth; sync = re-run `scripts/bootstrap.sh`)
- Project fields: created by `scripts/bootstrap.sh`; views are set up manually — `docs/setup/project-views.md`
- Native issue types: set automatically by the issue forms in `.github/ISSUE_TEMPLATE/`
