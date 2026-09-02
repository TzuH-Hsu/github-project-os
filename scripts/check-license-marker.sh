#!/usr/bin/env bash
# check-license-marker.sh — asserts bootstrap.sh's template-copyright constants
# still match LICENSE.
#
# Phase 9 decides "is this still the template's licence?" by looking for the
# exact line `Copyright (c) $TEMPLATE_COPYRIGHT_YEAR $TEMPLATE_COPYRIGHT_HOLDER`
# in LICENSE. If LICENSE is re-dated, or this template is forked and only one of
# the two files is updated, that test silently stops matching and phase 9 becomes
# a no-op for every adopter -- the original defect, with no symptom. This turns
# that drift into a red build within one PR.
#
# Template-only: an adopted repo has legitimately changed LICENSE, so the check
# no-ops there.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "docs/template" ] || [ -f "NOTICE" ]; then
  echo "SKIP: repo has been adopted — this check applies only to the template itself"
  exit 0
fi

read_const() {
  sed -n "s/^${1}=\"\(.*\)\"\$/\1/p" scripts/bootstrap.sh | head -n1
}

holder="$(read_const TEMPLATE_COPYRIGHT_HOLDER)"
year="$(read_const TEMPLATE_COPYRIGHT_YEAR)"

if [ -z "$holder" ] || [ -z "$year" ]; then
  echo "FAIL: could not read TEMPLATE_COPYRIGHT_HOLDER / TEMPLATE_COPYRIGHT_YEAR from scripts/bootstrap.sh"
  exit 1
fi

expected="Copyright (c) ${year} ${holder}"
if grep -qxF "$expected" LICENSE; then
  echo "PASS: LICENSE carries '${expected}' (matches scripts/bootstrap.sh)"
  exit 0
fi

echo "FAIL: LICENSE has no line '${expected}'"
echo "      bootstrap phase 9 would not recognise its own template licence, and would"
echo "      silently leave every adopter shipping the template author's copyright."
echo "      Fix: update TEMPLATE_COPYRIGHT_* in scripts/bootstrap.sh, or LICENSE, so they agree."
exit 1
