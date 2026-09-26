# Pulling template updates

> Template-product documentation — removed from your copy by the bootstrap de-template step. Keep a bookmark to the upstream copy if you plan to pull updates.

Repositories created from a template share no git history with it, so updates are a diff-and-apply exercise — deliberate, reviewable, no forced merges.

## Recommended flow

1. Watch upstream releases (GitHub → Watch → Custom → Releases). Each release's notes include a TLDR of what changed and why.
2. When a release interests you, diff your copy against it:

   ```bash
   git remote add template https://github.com/OWNER/TEMPLATE-REPO.git
   git config remote.template.tagOpt --no-tags
   git fetch template '+refs/tags/*:refs/template-tags/*'
   git diff HEAD refs/template-tags/vX.Y.Z -- .github/ skills/ Makefile scripts/
   ```

   The template's tags go under `refs/template-tags/`, never `refs/tags/`: the
   template and your repository both number releases `vX.Y.Z`, so a plain
   `git fetch template --tags` collides with your own tags (rejected, or
   overwritten with `--force`) and a later `git push --tags` would publish the
   template's to your remote. `tagOpt --no-tags` keeps an ordinary
   `git fetch template` from importing them either. If a clone already ran
   `--tags`, treat your remote as the only authority and push no tag from that
   clone — a tag `--force` overwrote now points at the template's commit. Run
   `git tag -l | xargs git tag -d` and `git fetch origin --tags`; that restores
   every tag your remote has. A tag of yours that was never pushed and shared a
   name with a template tag is gone from that clone: recreate it on its commit
   by hand (`git tag vX.Y.Z <sha>`).

3. Cherry-pick what you want by path. Good candidates: `skills/`, `.github/workflows/` (the labeler workflow only calls code that lives elsewhere — take them together with `scripts/issue-labeler.js`, `scripts/pr-lint.js`, their `*.test.js`, `scripts/check-node-tests.sh`, `scripts/check-label-forms.sh` and the two `check:` lines in the Makefile; `make check` fails if a workflow requires a `scripts/*.js` that is not there; if you graft the `Lint the pull request` step into a customized `ci.yml` instead of taking the file, take the `ci` job's `permissions:` block too — `issues: read` and `pull-requests: read` are what let the lint read the linked issue on a private repository), `scripts/check-*.sh` (rarely customized locally). Careful candidates: `Makefile` (your `test` target lives there), `.github/labels.yml` (your renamed `area:*` labels), `AGENTS.md` (your conventions).
4. Apply as a normal PR through your own CI. Never bulk-overwrite customized files.
5. Re-run `scripts/bootstrap.sh` if the update changed `labels.yml` or the ruleset — it syncs GitHub-side state to the files.

## What never gets pulled

Your `README.md`, `CHANGELOG.md`, version manifest, and anything the de-template step personalized — those are yours.
