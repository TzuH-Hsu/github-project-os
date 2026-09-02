# Runner selection

Every workflow in this template resolves its runner from one repository
variable:

```yaml
runs-on: ${{ fromJSON(vars.RUNNER_LABELS || '["ubuntu-latest"]') }}
```

Leave `RUNNER_LABELS` unset and behaviour is identical to hardcoding
`ubuntu-latest`. Set it once and all four workflows move together.

This is the single sanctioned exception to "customize the Makefile, never the
workflows" (`AGENTS.md`). It has to be an exception because GitHub resolves
`runs-on` when it schedules the job — before any `make` target exists to be
called — so it is the one adopter-facing knob the Makefile cannot own.

## Setting it

The value is a **JSON array**, not a bare string:

```bash
gh variable set RUNNER_LABELS --body '["ubuntu-latest-4-cores"]'
gh variable set RUNNER_LABELS --body '["self-hosted","linux","x64"]'
gh variable delete RUNNER_LABELS      # back to the default
```

## Get this wrong and the repository stops being mergeable

The tempting mistake is the bare string:

```bash
gh variable set RUNNER_LABELS --body 'ubuntu-latest'    # WRONG - not an array
```

Measured on this repository with a throwaway probe workflow, not assumed:

```text
workflow run  : completed, conclusion = failure
run message   : "This run likely failed because of a workflow file issue."
jobs created  : 0
check runs    : 0
```

`fromJSON` fails while the job is being scheduled, so **no job and no check run
are ever created.** For the `ci` workflow that is the worst case available: `ci`
is this repository's only required status check, so the pull request sits on
"Expected — waiting for status to be reported" forever, cannot merge, and the
only evidence is a failed run in the Actions tab whose message never mentions
the variable.

A valid-but-unknown label fails the same way from the other direction: the job
queues for a runner that never appears, for up to 24 hours.

**Recovery, which is not obvious from the symptom:**

```bash
gh variable delete RUNNER_LABELS
```

Then push any commit to re-trigger. Because of this, change the variable and
immediately open a throwaway pull request to confirm `ci` still reports, before
you rely on it.

## Hard constraint: linux x86_64 only

`scripts/install-ci-tools.sh` installs actionlint, gitleaks and lychee as
checksum-verified `linux_amd64` tarballs, and `require_supported_platform`
hard-fails on anything else. Point `RUNNER_LABELS` at `macos-latest` or an arm64
runner and `make ci-tools` fails at runtime with a message about `uname -m`,
which reads like a broken script rather than a misconfigured variable.

Supporting other architectures means adding per-tool asset names to that script,
not relaxing the guard.

## Self-hosted runners: read this first

Even a *compatible* self-hosted Linux x86_64 runner behaves differently from a
hosted one, because a hosted runner is destroyed after every job and yours is
not:

- `install_npm_global` and `install_python_tool` install **globally**, escaping
  `INSTALL_DIR` entirely.
- `require_install_consent` waves those through whenever `CI` is set, and GitHub
  Actions always sets it.
- `place_binary` uses `sudo` when `/usr/local/bin` is not writable, so the
  runner account needs passwordless sudo.

In practice: every run performs a real global `npm install -g` and
`pip install --user` on the runner host. That is fine on a throwaway container
and a slow accumulating mess on a long-lived VM. Prefer an ephemeral
self-hosted runner, or pre-install the five pinned tools into the image and
accept that `make ci-tools` will reinstall them anyway.

## Sizing: do not downsize to save money

The instinct to move CI onto a smaller, cheaper runner is usually wrong for a
repository shaped like this one, and `ci.yml`'s header already explains why for
the skip-CI case. The same arithmetic applies here:

- On a **public** repository, GitHub-hosted runners are free. A smaller runner
  saves exactly nothing.
- On a **private** repository, Actions minutes are billed **rounded up to the
  whole minute**. This template's lint job finishes in well under a minute, so
  it already bills the one-minute floor. A smaller, slower runner cannot go
  below that floor — it can only push the job over it and start billing two.
- Minimal images reinstall at runtime what a standard image preinstalls.
  Measured by an adopter on a 1 vCPU runner: the same lint job took 32 seconds
  to 2 minutes 7 seconds, against 21 to 45 seconds on `ubuntu-latest` — mostly
  spent installing markdownlint-cli2 via npm and yamllint via pip on one core.

Downsize only when a job **materially exceeds a minute** *and* you are past your
plan's included minutes. For a lint-shaped job neither is usually true.

Upsizing is the more common real need: a big test suite, or a compliance
requirement that builds run on your own hardware. That is what this variable is
for.

## See also

- `docs/setup/bootstrap.md` — the rest of the GitHub-side configuration
- `` `skills/github-actions-hygiene/SKILL.md` `` — why workflows stay thin
- `docs/adr/ADR-0005-runner-selection-variable.md` — why this is a variable
