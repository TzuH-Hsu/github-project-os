#!/usr/bin/env bash
# check-issue-labeler.sh — runs the issue labeler's tests.
#
# The labeler's logic lives in scripts/issue-labeler.js (ADR-0008); the
# workflow only calls it. scripts/issue-labeler.test.js exercises the pure
# functions and the run() entry point with stubbed GitHub clients, under
# plain node with no dependencies.
#
# node is a dependency of `make check` for this one script, like
# markdownlint-cli2 is for lint-docs; a missing node fails with an install
# hint the way the Makefile's other tool checks do — never a green skip.
#
# Exit status: 0 if the tests pass, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v node >/dev/null 2>&1 || { echo "install: node (e.g. brew install node) — needed for scripts/issue-labeler.test.js"; exit 1; }

if node --test --test-reporter=dot scripts/issue-labeler.test.js; then
  echo ""
  echo "OK: scripts/issue-labeler.test.js passed"
  echo "Summary: labeler tests passed"
  exit 0
fi
echo "FAIL: scripts/issue-labeler.test.js failed — rerun with: node --test scripts/issue-labeler.test.js"
echo "Summary: labeler tests FAILED"
exit 1
