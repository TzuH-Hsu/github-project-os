# ADR-0006: Coarse Type on accounts without native issue types

- **Status**: Accepted
- **Date**: 2026-09-02

## Context

The metadata contract (ADR-0003) gives coarse Type — Bug, Feature, Task — exactly one home: GitHub's native issue type, set by the issue form. Native issue types launched as an **organization-only** feature: on a personal-account repository `repos/{repo}/issue-types` returned 404 and the form's top-level `type:` key was silently ignored, leaving coarse Type with no home at all. GitHub has since rolled them out to user accounts — verified on this repository, a `User`-owned repo whose issue types were created 2026-08-21 — so the gap is narrower than when it was first reported, but it has not closed: the endpoint can still be unavailable, and the template must degrade correctly when it is. The condition to test is the endpoint, not the account type.

`.github/PROJECT_FIELDS.md` already allowed `type:bug` / `type:feature` labels as a fallback, but `.github/labels.yml` shipped no such labels. An adopter following that advice had to invent names, colours and descriptions and re-derive the single-home reasoning. This is the second pass at the same gap — commit `0f912c0` documented it once already.

The obvious fix, shipping the two labels active, is worse than it looks. An organization repo has native issue types; an active `type:bug` label would give coarse Type two homes, the exact dual-write ADR-0003 forbids. And an org adopter cannot undo it by deleting the label on GitHub, because the next `scripts/bootstrap.sh` sync recreates anything `labels.yml` still declares. The only durable fix is editing `labels.yml` — so the adopter edits that file either way.

## Decision

The two labels ship **commented out** in `.github/labels.yml`, with the reasoning inline, and bootstrap phase 2 enforces the contract in both directions.

1. **Commented, not active.** The adopter edits `labels.yml` regardless; the edit should fall on the account type that *wants* the label, not the one that must not have it. It also keeps the label budget in `skills/labels-and-taxonomy/SKILL.md` literally true, and makes activation a deliberate, reviewable act.
2. **Phase 2 checks both directions.** On the 404 path it reports whether the fallback is in use and offers it if not. On the success path — native types available *and* the fallback declared — it reports a single-home violation. That second half is what a "ship them active" design cannot provide at all.
3. **Phase 2 stays read-only.** It creates no labels and can still never `fail`; it is advisory.
4. **The check reads the declared set, not the live repo.** `parse_labels_yml` on `labels.yml` keeps `--dry-run` honest: a dry run creates nothing, so a live-repo query would report "no fallback" for a repo that is about to get one.
5. **No `type:task`.** An issue with neither label is a Task, and every Task already carries exactly one required `type:chore|ops|docs|security` subtype, so the Task query stays a positive predicate rather than a negation.
6. **The labels are applied by hand.** The labeler workflow never touches them.

## Consequences

- Personal-account adopters get correct names, colours, descriptions and reasoning, and opt in with one edit.
- Organization adopters do nothing and cannot accidentally acquire a second Type home.
- `.github/labels.yml` now depends on whole-line comments being invisible to its awk parser. That is verified — `/^[[:space:]]*-[[:space:]]*name:/` cannot match a `#`-led line — and the file header now says the comments are load-bearing so nobody "tidies" them into active entries.
- Bootstrap phase 2 grows a second failure mode to report, and the org branch of it cannot be exercised from a personal-account maintainer's own E2E.
- This does **not** supersede ADR-0003. It implements the escape hatch ADR-0003's authority map already allowed, and keeps single-home intact by making the two homes mutually exclusive rather than concurrent.

## Alternatives considered

- **Ship the labels active with a "delete these on org accounts" comment.** Rejected: a comment is not an enforcement mechanism, org repos get the dual-write by default, and deleting the label on GitHub is undone by the next sync.
- **Have phase 2 create the labels on the 404 path.** Rejected on mechanism, not principle: `main()` runs `phase_labels` before `phase_issue_types`, so the next run's phase 1 sees an undeclared label and prunes it (the default answer is yes), phase 2 recreates it, forever. Avoiding the loop would need a second `autorelease:*`-style prune exclusion for a class of labels no file declares, and it breaks `labels.yml`'s single-source-of-truth claim.
- **A Project `Type` single-select field.** Rejected: `docs/setup/project-views.md` caps the board at two custom fields, and a Project field is not queryable from `gh issue list`, which is the actual requirement.
- **Teach the labeler to apply them.** Deferred, not rejected. The coarse Type comes from the form's top-level `type:` key, which never appears in the issue body, and `context.payload.issue.type` is null on personal accounts. The only body-derived signal is heading-sniffing, which breaks the moment an adopter renames a form field — and adopters are told to customise these forms. Doing it properly needs a form-identity marker in all three forms plus labeler logic to read it.
