'use strict';
// pr-lint.js — the pull-request checks behind the `Lint the pull request`
// step in .github/workflows/ci.yml. Same shape as scripts/issue-labeler.js
// (ADR-0008): a pure lint() the tests exercise, and one run() the workflow
// calls through actions/github-script. Nothing here needs the token; it reads
// the pull_request payload and fails the job with a message that names the
// fix.
//
// What it enforces — the two conventions AGENTS.md states and the PR template
// carries, which were being broken silently:
//   1. the head branch is `<type>/<issue#>-<slug>`;
//   2. the body links an issue with a GitHub closing keyword (`Closes #N`);
//   3. the branch's issue number is among the linked ones.
// Bot branches (release-please, Dependabot) have no issue and are exempt.
//
// The PR body is untrusted input. It is only ever matched as text here; the
// numbers it yields go into a message, never into a command.

// The Conventional Commit types AGENTS.md lists (its "Branch" step is the one
// home for this list; pr-lint.test.js asserts the two are equal). The branch
// type mirrors them.
const TYPES = ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'test', 'perf'];
const BRANCH_RE = new RegExp(`^(${TYPES.join('|')})/(\\d+)-[a-z0-9][a-z0-9._-]*$`);
// GitHub's closing keywords: optional colon, then `#N`, `owner/repo#N`, or a
// full issue URL — the three forms GitHub itself links and auto-closes.
const CLOSES_RE = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+(?:https?:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/(\d+)|([\w.-]+\/[\w.-]+)?#(\d+))\b/gi;
const EXEMPT_BRANCH_PREFIXES = ['release-please--', 'dependabot/'];

function stripHtmlComments(text) {
  return String(text || '').replace(/<!--[\s\S]*?-->/g, '');
}

// Every issue the body closes: [{ repo: 'owner/name' | null, number }]. A
// reference qualified with this repository's own name counts as local.
function linkedIssues(body, repo) {
  const seen = new Map();
  for (const m of stripHtmlComments(body).matchAll(CLOSES_RE)) {
    const qualifier = m[1] || m[3] || null;
    const number = Number(m[2] || m[4]);
    const local = !qualifier || (repo && qualifier.toLowerCase() === String(repo).toLowerCase());
    const key = `${local ? '' : qualifier + '#'}${number}`;
    if (!seen.has(key)) seen.set(key, { repo: local ? null : qualifier, number });
  }
  return [...seen.values()];
}

function describe(ref) {
  return ref.repo ? `${ref.repo}#${ref.number}` : `#${ref.number}`;
}

// Pure. `repo` is 'owner/name' when known (run() passes context.repo), so a
// fully qualified self-reference is treated as local.
// Returns { exempt, problems: [string], branchIssue, linked: [number], cross: [string] }.
function lint({ headRef, body, repo }) {
  const ref = String(headRef || '');
  const refs = linkedIssues(body, repo);
  const linked = refs.filter((r) => !r.repo).map((r) => r.number);
  const cross = refs.filter((r) => r.repo).map(describe);
  if (EXEMPT_BRANCH_PREFIXES.some((p) => ref.startsWith(p))) {
    return { exempt: true, problems: [], branchIssue: null, linked, cross };
  }
  const problems = [];
  const branch = ref.match(BRANCH_RE);
  const branchIssue = branch ? Number(branch[2]) : null;
  if (!branch) {
    problems.push(
      `branch '${ref}' is not <type>/<issue#>-<slug> (types: ${TYPES.join(', ')}; e.g. fix/42-label-sync) — ` +
        'the usual slip is an empty issue number, which reads as "<type>/-<slug>"',
    );
  }
  if (linked.length === 0) {
    const tail = cross.length > 0
      ? ` (it closes ${cross.join(', ')} in another repository; an issue in this one is still required — AGENTS.md rule 1)`
      : ' (if this PR only advances an issue, give it a sub-issue it can close — skills/pr-authoring rule 5)';
    problems.push(
      'body links no issue in this repository — the PR template line is `Closes #<!-- issue number -->`; replace the comment ' +
        `with the number. Any GitHub closing keyword works: Closes / Fixes / Resolves, optional colon, #N or a full issue URL${tail}`,
    );
  }
  if (branchIssue !== null && linked.length > 0 && !linked.includes(branchIssue)) {
    problems.push(
      `branch names issue #${branchIssue} but the body closes #${linked.join(', #')} — one of them is wrong`,
    );
  }
  return { exempt: false, problems, branchIssue, linked, cross };
}

// Entry point for actions/github-script.
async function run({ context, core }) {
  const pr = context.payload.pull_request;
  if (!pr) {
    core.info('not a pull_request event — nothing to lint');
    return { exempt: true, problems: [] };
  }
  const repo = context.repo ? `${context.repo.owner}/${context.repo.repo}` : undefined;
  const result = lint({ headRef: pr.head && pr.head.ref, body: pr.body, repo });
  if (result.exempt) {
    core.info(`branch '${pr.head.ref}' is a bot branch — PR lint skipped`);
    return result;
  }
  if (result.problems.length > 0) {
    core.setFailed(`PR lint failed:\n- ${result.problems.join('\n- ')}`);
    return result;
  }
  const also = result.cross.length > 0 ? ` (and ${result.cross.join(', ')} elsewhere)` : '';
  core.info(`PR lint passed: branch issue #${result.branchIssue}, body closes #${result.linked.join(', #')}${also}`);
  return result;
}

module.exports = { run, lint, linkedIssues, describe, stripHtmlComments, TYPES, BRANCH_RE, CLOSES_RE, EXEMPT_BRANCH_PREFIXES };
