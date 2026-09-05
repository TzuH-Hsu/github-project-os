# ADR-0005: Runner selection is an adopter variable, not a workflow edit

- **Status**: Accepted
- **Date**: 2026-09-02

## Context

All four workflows hardcoded `runs-on: ubuntu-latest`. An adopter needing a different runner — self-hosted, larger, or on their own hardware for compliance — had to edit the workflow YAML.

That contradicts the template's own contract twice. `AGENTS.md` says "customize the Makefile, never the workflows", and `docs/template/design-principles.md` promises "workflow YAML stays untouched and upgradable". But `runs-on` is resolved by GitHub when it schedules the job, before any make target exists to be called, so it is the one adopter-facing property the Makefile physically cannot own. The rule was unsatisfiable for it, and following the rule was impossible.

It also degrades upgrades: `docs/template/upgrading.md` recommends bulk cherry-picking `.github/workflows/` precisely because it is rarely customized locally. A forked `runs-on` line makes every template update a manual merge.

## Decision

All four workflows resolve their runner from a single repository variable, defaulting to today's behaviour:

```yaml
runs-on: ${{ fromJSON(vars.RUNNER_LABELS || '["ubuntu-latest"]') }}
```

1. **One variable, not one per workflow.** Design principle 1 is "one good default beats three options". Three of the four jobs are trivial and identical in shape, so there is no plausible case for a bigger runner on the issue labeler but not on CI, and every extra name is another thing to typo. Splitting one variable into several later is easy; merging four after adopters have set them is not.
2. **A JSON array, via `fromJSON`.** Multi-label selection (`["self-hosted","linux","x64"]`) is the main reason self-hosted users need this at all.
3. **`AGENTS.md` is amended to name the exception**, rather than leaving it as folklore. An undocumented sanctioned exception is how a contract rots. `skills/github-actions-hygiene/SKILL.md` rule 1 is amended to match, or the skill would contradict the shipped workflows.
4. **The failure mode is documented at the point of risk**, in `ci.yml`'s header and in `docs/setup/runners.md`, with the recovery command.

## Consequences

- Adopters change runners from repository settings, and `.github/workflows/` stays byte-identical to upstream and cherry-pickable.
- **A new route into the "unmergeable repository" failure.** Measured with a throwaway probe workflow rather than assumed: with the variable set to the bare string `ubuntu-latest` instead of a JSON array, `fromJSON` fails during scheduling, the run completes with conclusion `failure` and the message "This run likely failed because of a workflow file issue", **zero jobs are created, and zero check runs are attached to the commit**. Applied to `ci.yml` — this repository's only required status check — the check is never reported, the pull request parks on "Expected — waiting for status", and the Actions tab never names the variable. Recovery is `gh variable delete RUNNER_LABELS`.
- The variable is bounded to linux x86_64 by `scripts/install-ci-tools.sh`, whose tarball tools ship no other assets. That constraint now has to be documented, because the failure surfaces as a `uname` message rather than a configuration error.
- Self-hosted runners acquire caveats that did not previously need writing down: the npm and pip installs escape `INSTALL_DIR` and run globally on the runner host every job.

## Alternatives considered

- **Four variables**, one per workflow, as the original field report proposed. Rejected per decision 1.
- **`${{ vars.RUNNER_LABELS || 'ubuntu-latest' }}` — a plain string, no `fromJSON`.** This removes the malformed-JSON footgun entirely, which is the single largest cost of this change. Rejected because it cannot express multi-label self-hosted selection, which is the primary use case. This is the closest call in this ADR; if the footgun proves worse in practice than the multi-label capability is worth, switching is a one-line change.
- **Leave `runs-on` hardcoded and accept that adopters fork the YAML.** Rejected: it makes two documented promises false, and the fork is permanent and invisible, whereas a misconfigured variable is transient and recoverable.
- **A `.github/actionlint.yaml` with declared self-hosted labels.** Only needed if `runs-on` held a hardcoded custom label; an expression bypasses actionlint's `runner-label` check entirely (verified against the pinned actionlint 1.7.12). Not needed.
