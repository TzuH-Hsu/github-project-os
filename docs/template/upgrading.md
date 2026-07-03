# Pulling template updates

> Template-product documentation — removed from your copy by the bootstrap de-template step. Keep a bookmark to the upstream copy if you plan to pull updates.

Repositories created from a template share no git history with it, so updates are a diff-and-apply exercise — deliberate, reviewable, no forced merges.

## Recommended flow

1. Watch upstream releases (GitHub → Watch → Custom → Releases). Each release's notes include a TLDR of what changed and why.
2. When a release interests you, diff your copy against it:

   ```bash
   git remote add template https://github.com/OWNER/TEMPLATE-REPO.git
   git fetch template --tags
   git diff HEAD template/vX.Y.Z -- .github/ skills/ Makefile scripts/
   ```

3. Cherry-pick what you want by path. Good candidates: `skills/`, `.github/workflows/`, `scripts/check-*.sh` (rarely customized locally). Careful candidates: `Makefile` (your `test` target lives there), `.github/labels.yml` (your renamed `area:*` labels), `AGENTS.md` (your conventions).
4. Apply as a normal PR through your own CI. Never bulk-overwrite customized files.
5. Re-run `scripts/bootstrap.sh` if the update changed `labels.yml` or the ruleset — it syncs GitHub-side state to the files.

## What never gets pulled

Your `README.md`, `CHANGELOG.md`, version manifest, and anything the de-template step personalized — those are yours.
