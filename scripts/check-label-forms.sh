#!/usr/bin/env bash
# check-label-forms.sh — label values repeated outside .github/labels.yml
# must still match it.
#
# .github/labels.yml is the taxonomy's single home (skills/labels-and-taxonomy
# rule 1), but three issue forms and the labeler workflow repeat some of its
# values as static text, and nothing else notices when they drift: the form
# still renders, the labeler still exits green, and ticking a box that names a
# label the repo no longer has applies nothing. A downstream adopter renamed
# area:* (as the template tells them to) and found out two weeks later.
#
# Verifies:
#   a. each issue form's Area checkboxes    == the area:* set in labels.yml
#   b. each issue form's Priority dropdown  == the priority:* set in labels.yml
#   c. the labeler's ALLOWED_PRIORITIES     == the priority:* set in labels.yml
#   d. task.yml's Subtype dropdown          == the labeler's ALLOWED_SUBTYPES
#                                           == the type:* set in labels.yml
#                                              minus type:bug / type:feature
#   e. type:bug / type:feature never appear in the Subtype dropdown — the
#      labeler's subtype allowlist exists so an untrusted issue body cannot
#      mint a coarse Type (ADR-0006); this pins that property.
#   f. no `- name:` entry in labels.yml is quoted — the header forbids it,
#      and bootstrap would create a label with the quotes in its name.
#
# Option text convention: the label name is the token before the first
# whitespace, e.g. `- label: "area:docs — Documentation and guides"` or
# `- "p0 — Critical, drop everything"`. Only the names are compared; the
# descriptive text is free. Names therefore cannot contain whitespace (the
# labeler reads the checked token the same way); any other character is fine
# with a labeler that reads labels.yml at run time — see h. for older ones.
#
# The labeler's area:* handling depends on its version, and this script may
# run in an adopted repo carrying an older copy, so it looks at the file:
#   g. if the labeler still declares a hardcoded ALLOWED_AREAS constant, that
#      constant must equal the area:* set (newer labelers read labels.yml at
#      run time and have no such constant — reported, not failed);
#   h. if the labeler still extracts area names with the `[a-z-]` grammar,
#      every area:* name must fit it, or the box would tick and apply nothing
#      (newer labelers take any non-whitespace token).
#   i. if the labeler still pre-filters priorities with /^(p[0-3])\b/ or
#      subtypes with a literal alternation, those must agree with the
#      allowlists — a consistently declared priority:p4 would otherwise pass
#      every set comparison and be ignored at run time (newer labelers match
#      the leading token and let the allowlist decide).
#
# Usage: scripts/check-label-forms.sh [labels-yml] [forms-dir] [labeler-yml]
#   Defaults: .github/labels.yml .github/ISSUE_TEMPLATE
#             .github/workflows/issue-labeler.yml
#   The overrides exist so the parser can be exercised against fixtures.
#
# Exit status: 0 if every check passes, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

LABELS_FILE="${1:-.github/labels.yml}"
FORMS_DIR="${2:-.github/ISSUE_TEMPLATE}"
LABELER_FILE="${3:-.github/workflows/issue-labeler.yml}"

FORMS="bug_report.yml feature_request.yml task.yml"
FALLBACK_TYPES="type:bug type:feature"

fail_count=0
ok_count=0

fail() {
  echo "FAIL: $1"
  fail_count=$((fail_count + 1))
}

ok() {
  echo "OK: $1"
  ok_count=$((ok_count + 1))
}

# Every `- name:` entry in labels.yml, one per line. The same reading as
# parse_labels_yml in scripts/bootstrap.sh and the labeler workflow: the name
# is the rest of the line, trimmed — no quote or comment stripping, so a
# quoted or inline-commented entry surfaces here as a mismatch, exactly as it
# would misbehave in bootstrap. Whole-line comments never match.
label_names() {
  awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$1"
}

# Option names of the form field whose `id:` is $2, in form $1. The field
# block starts at its `id:` line and ends at the next `- type:` field. Inside
# it, option lines are `- label: "..."` (checkboxes) or `- "..."` (dropdown);
# the name is the first whitespace-delimited token inside the quotes.
form_options() {
  awk -v want="$2" '
    /^[[:space:]]*-[[:space:]]*type:/ { inblock = 0 }
    /^[[:space:]]*id:[[:space:]]*/ {
      id = $0
      sub(/^[[:space:]]*id:[[:space:]]*/, "", id)
      sub(/[[:space:]]+$/, "", id)
      inblock = (id == want)
      next
    }
    inblock && /^[[:space:]]*-[[:space:]]*(label:[[:space:]]*)?["'"'"']/ {
      opt = $0
      sub(/^[[:space:]]*-[[:space:]]*(label:[[:space:]]*)?["'"'"']/, "", opt)
      sub(/[[:space:]].*$/, "", opt)
      sub(/["'"'"']$/, "", opt)
      print opt
    }
  ' "$1"
}

# Items of a `const NAME = ['a', 'b'];` line in the labeler, one per line.
labeler_list() {
  grep -E "const $2 = \[" "$1" \
    | sed -E "s/.*\[([^]]*)\].*/\1/" \
    | tr ',' '\n' \
    | sed -E "s/[[:space:]'\"]//g" \
    | grep -v '^$' || true
}

# stdin filter: prefix every non-empty line, sort, dedupe.
with_prefix() { sed "s/^/$1/" | grep -v "^$1\$" | sort -u || true; }

# compare <what> <expected-lines> <found-lines> <hint>
compare() {
  local what="$1" expected="$2" found="$3" hint="$4"
  if [ "$expected" = "$found" ]; then
    ok "$what"
  else
    fail "$what"
    echo "      expected: $(printf '%s\n' "$expected" | tr '\n' ' ')"
    echo "      found:    $(printf '%s\n' "$found" | tr '\n' ' ')"
    [ -n "$hint" ] && echo "      $hint"
  fi
}

if [ ! -f "$LABELS_FILE" ]; then
  fail "$LABELS_FILE not found — it is the single home for every label value"
  echo ""
  echo "Summary: $ok_count OK, $fail_count FAIL"
  exit 1
fi

all_names="$(label_names "$LABELS_FILE")"

# --- f: quoting that bootstrap would pass through verbatim
quoted="$(printf '%s\n' "$all_names" | grep -E '^["'"'"']' || true)"
if [ -n "$quoted" ]; then
  fail "$LABELS_FILE has quoted name entries — the header rules out YAML quoting, and bootstrap would create the label with the quotes in it: $(printf '%s\n' "$quoted" | tr '\n' ' ')"
else
  ok "$LABELS_FILE name entries are unquoted"
fi
areas="$(printf '%s\n' "$all_names" | grep '^area:' | sort -u || true)"
priorities="$(printf '%s\n' "$all_names" | grep '^priority:' | sort -u || true)"
subtypes="$(printf '%s\n' "$all_names" | grep '^type:' | grep -v -x -e 'type:bug' -e 'type:feature' | sort -u || true)"

# --- a/b: forms vs labels.yml
for form in $FORMS; do
  path="$FORMS_DIR/$form"
  if [ ! -f "$path" ]; then
    echo "SKIP: $path not present"
    continue
  fi
  found_areas="$(form_options "$path" area | with_prefix '')"
  compare "$form Area options match the area:* set in $LABELS_FILE" "$areas" "$found_areas" \
    "fix: one \`- label: \"<name> — <text>\"\` line per area:* entry, under the field whose id is 'area'"
  found_prio="$(form_options "$path" priority | with_prefix 'priority:')"
  compare "$form Priority options match the priority:* set in $LABELS_FILE" "$priorities" "$found_prio" \
    "fix: one \`- \"<pN> — <text>\"\` line per priority:* entry, under the field whose id is 'priority'"
done

# --- c/d: labeler constants
if [ ! -f "$LABELER_FILE" ]; then
  echo "SKIP: $LABELER_FILE not present"
else
  lab_prio="$(labeler_list "$LABELER_FILE" ALLOWED_PRIORITIES | with_prefix 'priority:')"
  compare "labeler ALLOWED_PRIORITIES matches the priority:* set in $LABELS_FILE" "$priorities" "$lab_prio" \
    "fix: edit the ALLOWED_PRIORITIES constant in $LABELER_FILE"
  lab_sub="$(labeler_list "$LABELER_FILE" ALLOWED_SUBTYPES | with_prefix 'type:')"
  compare "labeler ALLOWED_SUBTYPES matches the type:* set in $LABELS_FILE minus the coarse-Type fallback labels" "$subtypes" "$lab_sub" \
    "fix: edit the ALLOWED_SUBTYPES constant in $LABELER_FILE (never add bug or feature to it)"

  # --- g: older labelers hardcode the area allowlist
  if grep -qE 'const ALLOWED_AREAS = \[' "$LABELER_FILE"; then
    lab_areas="$(labeler_list "$LABELER_FILE" ALLOWED_AREAS | with_prefix '')"
    compare "labeler ALLOWED_AREAS matches the area:* set in $LABELS_FILE" "$areas" "$lab_areas" \
      "fix: edit the ALLOWED_AREAS constant in $LABELER_FILE — or take the labeler that reads labels.yml at run time (github-project-os #45)"
  else
    ok "labeler declares no ALLOWED_AREAS constant (reads area:* from $LABELS_FILE at run time)"
  fi

  # --- i: older labelers duplicate the allowlists as regexes
  if grep -qF '/^(p[0-3])\b/' "$LABELER_FILE"; then
    off="$(printf '%s\n' "$priorities" | grep -vE '^priority:p[0-3]$' || true)"
    if [ -n "$off" ]; then
      fail "labeler pre-filters priorities with /^(p[0-3])\\b/ and these are outside it (declared everywhere, ignored at run time): $(printf '%s\n' "$off" | tr '\n' ' ')"
      echo "      fix: take the labeler that matches the leading token against ALLOWED_PRIORITIES (github-project-os #45), or keep priorities within p0-p3"
    else
      ok "every priority:* fits the labeler's /^(p[0-3])\\b/ pre-filter"
    fi
  fi
  sub_re="$(grep -oE '/\^\(([a-z|]+)\)\\b/' "$LABELER_FILE" | grep -v 'p\[0-3\]' | head -n1 | sed -E 's#^/\^\((.*)\)\\b/$#\1#' || true)"
  if [ -n "$sub_re" ]; then
    re_set="$(printf '%s\n' "$sub_re" | tr '|' '\n' | with_prefix 'type:')"
    compare "labeler subtype pre-filter regex /^($sub_re)\\b/ matches ALLOWED_SUBTYPES" "$lab_sub" "$re_set" \
      "fix: take the labeler that matches the leading token against ALLOWED_SUBTYPES (github-project-os #45), or keep the regex and the constant equal"
  fi

  # --- h: older labelers only parse [a-z-] area names
  if grep -qF '/area:[a-z-]+/' "$LABELER_FILE"; then
    unparsable="$(printf '%s\n' "$areas" | grep -vE '^area:[a-z-]+$' || true)"
    if [ -n "$unparsable" ]; then
      fail "labeler extracts area names with /area:[a-z-]+/ and these names do not fit it (the box would tick and apply nothing): $(printf '%s\n' "$unparsable" | tr '\n' ' ')"
      echo "      fix: rename to lowercase letters and hyphens, or take the labeler from github-project-os #45"
    else
      ok "every area:* name fits the labeler's /area:[a-z-]+/ grammar"
    fi
  fi
  task="$FORMS_DIR/task.yml"
  if [ -f "$task" ]; then
    task_sub="$(form_options "$task" subtype | with_prefix 'type:')"
    compare "task.yml Subtype options match the labeler's ALLOWED_SUBTYPES" "$lab_sub" "$task_sub" \
      "fix: one \`- \"<subtype> — <text>\"\` line per subtype, under the field whose id is 'subtype'"
    # --- e: the security property
    leaked=""
    for t in $FALLBACK_TYPES; do
      if printf '%s\n' "$task_sub" | grep -qx "$t"; then leaked="$leaked $t"; fi
    done
    if [ -n "$leaked" ]; then
      fail "task.yml Subtype dropdown offers$leaked — the coarse-Type fallback labels are applied by hand only, never from a form field an untrusted body can spoof (ADR-0006)"
    else
      ok "task.yml Subtype dropdown offers neither type:bug nor type:feature"
    fi
  fi
fi

echo ""
echo "Summary: $ok_count OK, $fail_count FAIL"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
