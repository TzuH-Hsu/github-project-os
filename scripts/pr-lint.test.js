'use strict';
// pr-lint.test.js — exercises scripts/pr-lint.js under plain node.
// Run by scripts/check-node-tests.sh from `make check`.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { lint, linkedIssues, run, TYPES } = require('./pr-lint.js');
const numbers = (body, repo) => linkedIssues(body, repo).filter((r) => !r.repo).map((r) => r.number);

const GOOD_BODY = '## Summary\n\nx\n\n## Related issue\n\nCloses #42\n';

test('a conforming PR passes', () => {
  const r = lint({ headRef: 'fix/42-label-sync', body: GOOD_BODY });
  assert.deepEqual(r, { exempt: false, why: null, problems: [], branchIssue: 42, linked: [42], cross: [] });
});

test("TYPES equals the list in AGENTS.md's Branch step (the one home for it)", () => {
  const agents = fs.readFileSync(path.join(__dirname, '..', 'AGENTS.md'), 'utf8');
  const line = agents.split('\n').find((l) => l.includes('**Branch**') && l.includes('<type>/<issue#>-<slug>'));
  assert.ok(line, 'AGENTS.md Branch step not found');
  const listed = [...line.matchAll(/`([a-z]+)`/g)].map((m) => m[1]);
  assert.deepEqual(listed, TYPES);
});

test('the six-PR failure shape: empty issue slot in the branch and a bare "Closes #"', () => {
  const r = lint({ headRef: 'chore/-initial-version-docs', body: 'Closes #\n' });
  assert.equal(r.problems.length, 2);
  assert.match(r.problems[0], /not <type>\/<issue#>-<slug>/);
  assert.match(r.problems[1], /links no issue/);
});

test('the untouched template line still fails: the number is inside an HTML comment', () => {
  const r = lint({ headRef: 'fix/42-x', body: 'Closes #<!-- issue number -->' });
  assert.deepEqual(r.linked, []);
  assert.equal(r.problems.length, 1);
});

test('a closing keyword hidden inside an HTML comment does not count', () => {
  assert.deepEqual(numbers('<!-- Closes #12 -->\nsome text'), []);
});

test('all GitHub closing keywords, the colon form and the full URL form are recognised, case-insensitively', () => {
  assert.deepEqual(numbers('closes #1 Fixes #2 RESOLVED #3 close #5 resolves #6 Closes: #9 CLOSES: #10'), [1, 2, 3, 5, 6, 9, 10]);
  assert.deepEqual(numbers('Closes https://github.com/o/r/issues/77', 'o/r'), [77]);
  assert.deepEqual(numbers('Closes o/r#78', 'O/R'), [78]);
  assert.deepEqual(numbers('see #7 and refs #8 closes#9 Closes:#10'), []);
});

test('cross-repository references are kept apart from local ones and never satisfy the branch number', () => {
  const only = lint({ headRef: 'fix/4-x', body: 'Closes other/repo#4', repo: 'o/r' });
  assert.deepEqual(only.linked, []);
  assert.deepEqual(only.cross, ['other/repo#4']);
  assert.equal(only.problems.length, 1);
  assert.match(only.problems[0], /closes other\/repo#4 in another repository/);
  const both = lint({ headRef: 'fix/12-x', body: 'Closes #12, closes https://github.com/other/repo/issues/4', repo: 'o/r' });
  assert.deepEqual(both, { exempt: false, why: null, problems: [], branchIssue: 12, linked: [12], cross: ['other/repo#4'] });
});

test('a Refs-only body is told to split the work into a sub-issue', () => {
  const r = lint({ headRef: 'feat/3-x', body: 'Refs #3' });
  assert.match(r.problems[0], /sub-issue it can close/);
});

test('exactly one local issue: a second Closes fails (one issue per PR), a mismatched one fails', () => {
  const two = lint({ headRef: 'feat/10-x', body: 'Closes #10\nCloses #11' });
  assert.equal(two.problems.length, 1);
  assert.match(two.problems[0], /one issue per PR/);
  const r = lint({ headRef: 'feat/10-x', body: 'Closes #11' });
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /branch names issue #10 but the body closes #11/);
  assert.deepEqual(lint({ headRef: 'feat/10-x', body: 'Closes #10\nCloses #10' }).problems, []); // same issue twice is one issue
});

test('branch grammar: every CONTRIBUTING type, lowercase slug with dots/underscores; rejects others', () => {
  for (const t of ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'test', 'perf']) {
    assert.deepEqual(lint({ headRef: `${t}/7-a.b_c-1`, body: 'Closes #7' }).problems, []);
  }
  for (const bad of ['Feat/7-x', 'feature/7-x', 'fix/7', 'fix/7-', 'fix/x-7', 'fix-7-x', 'main', 'hotfix/7-x']) {
    assert.equal(lint({ headRef: bad, body: 'Closes #7' }).problems.length, 1, bad);
  }
});

test('bot PRs are exempt by author or by the release-please label — never by branch name', () => {
  assert.equal(lint({ headRef: 'release-please--branches--main', body: ':robot:', author: 'github-actions[bot]' }).exempt, true);
  assert.equal(lint({ headRef: 'dependabot/github_actions/actions-f3c1f23acc', body: '', author: 'dependabot[bot]' }).exempt, true);
  // release-please run with a PAT: human author, but the label it applies is proof enough
  assert.equal(lint({ headRef: 'release-please--branches--main', body: ':robot:', author: 'someone', labels: ['autorelease: pending'] }).exempt, true);
  // a fork author borrowing the bot branch name gets the full lint
  const spoof = lint({ headRef: 'release-please--branches--main', body: 'hi', author: 'someone', labels: [] });
  assert.equal(spoof.exempt, false);
  assert.equal(spoof.problems.length, 2);
  assert.equal(lint({ headRef: 'dependabot/x', body: '', author: 'someone' }).exempt, false);
});

test('run: fails the job with every problem listed, passes with an info line, skips non-PR events', async () => {
  const out = [];
  const core = { info: (m) => out.push(['info', m]), setFailed: (m) => out.push(['failed', m]) };
  await run({ context: { payload: { pull_request: { head: { ref: 'chore/-x' }, body: 'Closes #' } } }, core });
  assert.equal(out.length, 1);
  assert.equal(out[0][0], 'failed');
  assert.match(out[0][1], /^PR lint failed:\n- branch .*\n- body links no issue/s);
  out.length = 0;
  await run({ context: { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { head: { ref: 'fix/42-x' }, body: GOOD_BODY + 'Closes o/r#42\n' } } }, core });
  assert.deepEqual(out, [['info', 'PR lint passed: branch issue #42, body closes #42']]);
  out.length = 0;
  await run({ context: { payload: {} }, core });
  assert.equal(out[0][0], 'info');
  out.length = 0;
  await run({ context: { payload: { pull_request: { head: { ref: 'release-please--branches--main' }, body: '', user: { login: 'github-actions[bot]' }, labels: [{ name: 'autorelease: pending' }] } } }, core });
  assert.deepEqual(out, [['info', 'PR lint skipped: opened by github-actions[bot]']]);
});
