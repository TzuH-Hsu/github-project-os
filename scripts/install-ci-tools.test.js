// SPDX-License-Identifier: MIT
'use strict';
// install-ci-tools.test.js — exercises the release downloads in
// scripts/install-ci-tools.sh and the workflow steps that cache them.
// Run by scripts/check-node-tests.sh from `make check`.
//
// The script runs for real under bash against a fake `curl` that serves
// release assets from a temporary directory and logs every call, and a fake
// `uname` that reports linux x86_64. Assets are checked by the real
// `sha256sum` against a copy of the script whose ACTIONLINT_SHA256 pin names
// the fake asset. No release checksum file exists in these tests, so a code
// path that still relied on one would fail here.
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const KIT = path.join(__dirname, 'install-ci-tools.sh');
const KIT_TEXT = fs.readFileSync(KIT, 'utf8');
const HEX64 = /^[0-9a-f]{64}$/;

const FAKE_CURL = `#!/usr/bin/env bash
# Serves https://github.com/<owner>/<repo>/releases/download/<tag>/<file>
# from $FAKE_RELEASES/<owner>/<repo>/<tag>/<file>, like \`curl -f -o <file>\`.
printf '%s\\n' "$*" >> "$FAKE_CURL_LOG"
out="" url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry | --retry-delay | --connect-timeout | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "\${FAKE_CURL_FAIL:-}" ] && exit 22
path="\${url#https://github.com/}"
src="$FAKE_RELEASES/\${path/\\/releases\\/download\\///}"
[ -n "$out" ] && [ -f "$src" ] || exit 22
cp "$src" "$out"
`;

const FAKE_UNAME = `#!/bin/sh
case "$1" in
  -s) echo Linux ;;
  -m) echo x86_64 ;;
  *) echo Linux ;;
esac
`;

function kitPin(name) {
  const m = KIT_TEXT.match(new RegExp(`^${name}="([^"]+)"`, 'm'));
  assert.ok(m, `${name} not found in install-ci-tools.sh`);
  return m[1];
}

const sha256 = (data) => crypto.createHash('sha256').update(data).digest('hex');

const VERSION = kitPin('ACTIONLINT_VERSION');
const TOOL = 'actionlint';
const REPO = 'rhysd/actionlint';
const TAG = `v${VERSION}`;
const ASSET = `actionlint_${VERSION}_linux_amd64.tar.gz`;
const CHECKSUMS = `actionlint_${VERSION}_checksums.txt`;

let t; // per-test state

function tarball(dir) {
  // a gzipped tarball holding one executable named after the tool
  const src = path.join(dir, 'tar-src');
  fs.mkdirSync(src);
  fs.writeFileSync(path.join(src, TOOL), `#!/bin/sh\necho fake ${TOOL}\n`, { mode: 0o755 });
  const out = path.join(dir, 'asset.tar.gz');
  const r = spawnSync('tar', ['-czf', out, '-C', src, TOOL]);
  assert.equal(r.status, 0, String(r.stderr));
  return fs.readFileSync(out);
}

function publish(root, bytes) {
  const folder = path.join(root, REPO, TAG);
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, ASSET), bytes);
  return folder;
}

function pinnedScript(digest) {
  const pinned = KIT_TEXT.replace(/^ACTIONLINT_SHA256="[^"]*"/m, `ACTIONLINT_SHA256="${digest}"`);
  assert.notEqual(pinned, KIT_TEXT, 'ACTIONLINT_SHA256 pin line not found');
  const script = path.join(t.tmp, 'install-ci-tools.sh');
  fs.writeFileSync(script, pinned);
  return script;
}

function run({ cache = true, env = {} } = {}) {
  const fullEnv = {
    PATH: `${t.fakebin}:/usr/bin:/bin:/usr/sbin:/sbin`,
    HOME: t.tmp,
    INSTALL_DIR: t.installDir,
    FAKE_RELEASES: t.releases,
    FAKE_CURL_LOG: t.log,
    ...(cache ? { CI_TOOLS_CACHE_DIR: t.cache } : {}),
    ...env,
  };
  return spawnSync('bash', [t.script, TOOL], { cwd: ROOT, env: fullEnv, encoding: 'utf8', timeout: 60000 });
}

const curlCalls = () => fs.readFileSync(t.log, 'utf8').split('\n').filter(Boolean);
const cachedAsset = () => path.join(t.cache, REPO, TAG, ASSET);
const installed = () => path.join(t.installDir, TOOL);

function assertInstalled(r) {
  assert.equal(r.status, 0, r.stderr);
  assert.ok(fs.existsSync(installed()), r.stdout);
}

function assertNothingInstalled(r) {
  assert.notEqual(r.status, 0, r.stdout);
  assert.ok(!fs.existsSync(installed()));
}

function filesUnder(dir) {
  return fs.readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile()).map((e) => e.name).sort();
}

beforeEach(() => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'install-ci-tools-'));
  t = {
    tmp,
    releases: path.join(tmp, 'releases'),
    cache: path.join(tmp, 'cache'),
    installDir: path.join(tmp, 'bin'),
    log: path.join(tmp, 'curl.log'),
    fakebin: path.join(tmp, 'fakebin'),
  };
  fs.writeFileSync(t.log, '');
  fs.mkdirSync(t.fakebin);
  fs.writeFileSync(path.join(t.fakebin, 'curl'), FAKE_CURL, { mode: 0o755 });
  fs.writeFileSync(path.join(t.fakebin, 'uname'), FAKE_UNAME, { mode: 0o755 });
  t.good = tarball(tmp);
  publish(t.releases, t.good);
  t.script = pinnedScript(sha256(t.good));
});

afterEach(() => fs.rmSync(t.tmp, { recursive: true, force: true }));

test('every tarball tool has a sha256 pin next to its version pin', () => {
  for (const name of ['ACTIONLINT', 'GITLEAKS', 'LYCHEE']) {
    assert.match(kitPin(`${name}_SHA256`), HEX64, name);
  }
});

test('only the asset is downloaded, with retries', () => {
  const r = run({ cache: false });
  assertInstalled(r);
  const calls = curlCalls();
  assert.equal(calls.length, 1, calls.join('\n'));
  assert.ok(calls[0].endsWith(`/${TAG}/${ASSET}`), calls[0]);
  assert.match(calls[0], /--retry 5\b/);
  assert.match(calls[0], /--retry-all-errors/);
  assert.match(calls[0], /--retry-delay [1-9][0-9]*/);
});

test('a failed download installs nothing', () => {
  assertNothingInstalled(run({ cache: false, env: { FAKE_CURL_FAIL: '1' } }));
});

test('a cache miss downloads and stores only the verified asset', () => {
  const r = run();
  assertInstalled(r);
  assert.equal(curlCalls().length, 1);
  assert.deepEqual(fs.readFileSync(cachedAsset()), t.good);
  assert.deepEqual(filesUnder(t.cache), [ASSET]);
});

test('a cache hit downloads nothing and still checks the pin', () => {
  publish(t.cache, t.good);
  const r = run({ env: { FAKE_CURL_FAIL: '1' } });
  assertInstalled(r);
  assert.deepEqual(curlCalls(), []);
  assert.match(r.stdout, new RegExp(`${ASSET}: OK`));
  assert.match(r.stdout, /from the cache/);
});

test('a tampered cached asset is deleted and downloaded again, whatever checksum file sits next to it', () => {
  const folder = publish(t.cache, Buffer.from('tampered'));
  fs.writeFileSync(path.join(folder, CHECKSUMS), `${sha256(Buffer.from('tampered'))}  ${ASSET}\n`);
  const r = run();
  assertInstalled(r);
  assert.match(r.stderr, /does not match its pinned sha256/);
  assert.equal(curlCalls().length, 1);
  assert.deepEqual(fs.readFileSync(cachedAsset()), t.good);
  assert.equal(fs.readFileSync(installed(), 'utf8'), `#!/bin/sh\necho fake ${TOOL}\n`);
});

test('a tampered cached asset is rejected when the release host is down', () => {
  publish(t.cache, Buffer.from('tampered'));
  const r = run({ env: { FAKE_CURL_FAIL: '1' } });
  assertNothingInstalled(r);
  assert.ok(!fs.existsSync(cachedAsset()));
});

test('a download that does not match the pin installs and caches nothing, and names the checksum file', () => {
  publish(t.releases, Buffer.from('tampered'));
  const r = run();
  assertNothingInstalled(r);
  assert.ok(r.stderr.includes(CHECKSUMS), r.stderr);
  assert.ok(!fs.existsSync(cachedAsset()));
});

test('storing a version drops the other versions of that tool', () => {
  const old = path.join(t.cache, REPO, 'v0.0.1');
  fs.mkdirSync(old, { recursive: true });
  fs.writeFileSync(path.join(old, 'old.tar.gz'), 'old');
  assertInstalled(run());
  assert.deepEqual(fs.readdirSync(path.join(t.cache, REPO)), [TAG]);
});

test('a relative cache directory is resolved against the caller, not the scratch directory', () => {
  const relative = path.relative(ROOT, t.cache);
  assertInstalled(run({ cache: false, env: { CI_TOOLS_CACHE_DIR: relative } }));
  assert.ok(fs.existsSync(cachedAsset()));
});

// --- the workflow steps around `make ci-tools` ---------------------------------
function restoreStep(workflow) {
  const text = fs.readFileSync(path.join(ROOT, '.github', 'workflows', workflow), 'utf8');
  const start = text.indexOf('- name: Restore CI tool downloads');
  assert.ok(start >= 0, `${workflow}: no "Restore CI tool downloads" step`);
  const step = text.slice(start, text.indexOf('- name:', start + 1));
  return { text, step, key: (step.match(/^\s+key: (.+)$/m) || [])[1] };
}

test('ci.yml and maintenance.yml restore the same cache key, exact match only', () => {
  const ci = restoreStep('ci.yml');
  const maintenance = restoreStep('maintenance.yml');
  assert.ok(ci.key, 'ci.yml restore step has no key');
  assert.equal(maintenance.key, ci.key);
  for (const { text } of [ci, maintenance]) {
    assert.doesNotMatch(text, /^\s+restore-keys:/m);
    assert.match(text, /CI_TOOLS_CACHE_DIR: \$\{\{ runner\.temp \}\}\/ci-tools-cache/);
  }
});

test('ci.yml saves under the key it restored, only on a miss; maintenance.yml saves nothing', () => {
  const ci = restoreStep('ci.yml');
  const save = ci.text.slice(ci.text.indexOf('- name: Save CI tool downloads'));
  assert.match(save, /if: steps\.ci-tools-cache\.outputs\.cache-hit != 'true'/);
  assert.match(save, /key: \$\{\{ steps\.ci-tools-cache\.outputs\.cache-primary-key \}\}/);
  assert.doesNotMatch(restoreStep('maintenance.yml').text, /actions\/cache\/save/);
});
