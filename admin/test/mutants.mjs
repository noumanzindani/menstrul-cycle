// Proves that `admin.test.mjs` actually discriminates.
//
// This repo has shipped eight tests that passed with their own fix reverted,
// and a review recently found three more. A green suite is not evidence; a
// suite that goes RED when the thing it claims to test is removed is. So rather
// than trusting each assertion to be load-bearing, this re-runs the WHOLE suite
// once per mutant — the panel's source with exactly one guard removed — and
// fails unless the named test(s) go red.
//
// Mutants are applied to a COPY of the tree in a temp directory, never to the
// working files, so an interrupted run cannot leave a sabotaged source behind.
// The copy mirrors enough of the repo for the suite's relative imports to
// resolve (`admin/src`, `admin/test`, `firebase_test/emulator.mjs` and
// `firestore.rules`), with `node_modules` symlinked.
//
// Runs inside `firebase emulators:exec`, same as the suite itself.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ADMIN = path.join(here, '..');
const REPO = path.join(ADMIN, '..');

/**
 * Each mutant removes ONE guard and names the test(s) that must go red.
 *
 * `from` is matched literally; a mutant whose anchor no longer exists is a hard
 * failure, so this file cannot silently rot as the panel is edited.
 */
const MUTANTS = [
  // --- identity ----------------------------------------------------------
  {
    name: 'IAP signature verification dropped',
    file: 'src/iap.js',
    from: "if (!signed) throw new IdentityError('IAP assertion signature is invalid');",
    to: 'if (false) throw new IdentityError(String(signed));',
    expect: ['an assertion signed by a DIFFERENT key is refused'],
  },
  {
    name: 'the IAP audience check dropped',
    file: 'src/iap.js',
    from: 'if (payload.aud !== audience) {',
    to: 'if (false) {',
    expect: ['an assertion minted for ANOTHER service is refused'],
  },
  {
    name: 'the algorithm check dropped (alg confusion)',
    file: 'src/iap.js',
    from: "if (header.alg !== 'ES256') {",
    to: 'if (false) {',
    expect: ['an "alg: none" assertion is refused'],
  },
  {
    name: 'the issuer check dropped',
    file: 'src/iap.js',
    from: 'if (payload.iss !== IAP_ISSUER) {',
    to: 'if (false) {',
    expect: ['an assertion from an issuer other than IAP is refused'],
  },
  {
    name: 'the expiry check dropped',
    file: 'src/iap.js',
    from: "if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < seconds) {",
    to: 'if (false) {',
    expect: ['an expired assertion is refused'],
  },
  {
    name: 'the missing-header check dropped',
    file: 'src/iap.js',
    from: "if (!token) throw new IdentityError('no IAP assertion header present');",
    to: 'if (token === undefined && false) throw new IdentityError("x");',
    expect: ['a request with NO assertion header is refused'],
  },
  {
    name: 'the ADMIN_EMAILS allowlist dropped',
    file: 'src/iap.js',
    from: 'if (!adminEmails.has(email)) {',
    to: 'if (false) {',
    expect: ['a VERIFIED identity that is not on the allowlist is refused'],
  },
  {
    name: 'the same-origin check on POST dropped',
    file: 'src/app.js',
    from: 'if (originHost && host && originHost === host) return next();',
    to: 'return next();',
    expect: ['a cross-origin form post is refused before anything is read'],
  },
  {
    name: 'the dev-bypass emulator interlock dropped',
    file: 'src/env.js',
    from: 'if (requestedDevIdentity && !emulatorHost) {',
    to: 'if (false) {',
    expect: ['the dev identity bypass is refused without an emulator host'],
  },
  {
    name: 'the empty-allowlist startup check dropped',
    file: 'src/env.js',
    from: 'if (adminEmails.size === 0) {',
    to: 'if (false) {',
    expect: ['an empty allowlist refuses to start'],
  },

  // --- audit -------------------------------------------------------------
  {
    name: 'audit written AFTER the content instead of before',
    file: 'src/audit.js',
    from: '  await audit.record(entry);\n  return read();',
    to: '  const result = await read();\n  await audit.record(entry);\n  return result;',
    expect: [
      'the audit record is written BEFORE any health record is read',
      'a FAILED audit write blocks the read entirely',
    ],
  },
  {
    name: 'the audit write made a no-op',
    file: 'src/audit.js',
    from: '      await doc.create({',
    to: '      await Promise.resolve({',
    expect: [
      'the audit record is written BEFORE any health record is read',
      'the audit record names the actor, the target, the view and the reason',
      'viewing account metadata is audited too, without demanding a reason',
    ],
  },
  {
    name: "the audit log's own required-reason check dropped",
    file: 'src/audit.js',
    from: 'if (CONTENT_VIEWS.has(view) && trimmed.length === 0) {',
    to: 'if (false) {',
    expect: ['an empty reason is refused, with no audit record and no read'],
  },
  {
    name: "the route's required-reason check dropped",
    file: 'src/app.js',
    from: 'if (reason.trim().length === 0) {',
    to: 'if (false) {',
    expect: ['an empty reason is refused, with no audit record and no read'],
  },

  // --- read-only ---------------------------------------------------------
  {
    name: 'the mutating-method denylist emptied',
    file: 'src/readonly.js',
    from: "  'set',\n  'update',\n  'delete',",
    to: "  'noop_set',\n  'noop_update',\n  'noop_delete',",
    expect: ['every mutating method throws on the panel handle'],
  },
  {
    name: 'snapshot.ref left unwrapped (escape hatch back to a writable ref)',
    file: 'src/readonly.js',
    from: "if (property === 'ref') return readOnly(value, `${label}.ref`);",
    to: "if (property === 'ref' && false) return readOnly(value, `${label}.ref`);",
    expect: ['a snapshot cannot be used to escape back to a writable reference'],
  },
  {
    name: 'a write to health data introduced on the records path',
    file: 'src/records.js',
    from: '  const snapshot = await query.limit(limit).get();',
    to:
      "  await db.collection(dailyLogsPath(uid)).doc('2026-08-04').set({ flow: 0 });\n" +
      '  const snapshot = await query.limit(limit).get();',
    expect: ['driving EVERY endpoint leaves the users subtree byte-identical'],
  },

  // --- statistics --------------------------------------------------------
  {
    name: 'count() aggregation replaced by a document sweep',
    file: 'src/stats.js',
    from:
      '    const snapshot = await query.count().get();\n' +
      '    return { count: snapshot.data().count };',
    to: '    const snapshot = await query.get();\n    return { count: snapshot.size };',
    expect: ['statistics use count() aggregation and NEVER sweep documents'],
  },
  {
    name: 'the pending-deletion subtraction dropped',
    file: 'src/stats.js',
    from: 'pending === null ? null : Math.max(0, accounts.total - pending),',
    to: 'accounts.total,',
    expect: ['the dashboard counts pending deletions and subtracts them'],
  },
  {
    name: 'activity windows ignore the Auth last-seen timestamp',
    file: 'src/stats.js',
    from: '      const seen = lastSeenAt(record);',
    to: '      const seen = new Date(now);',
    expect: ['activity windows are driven by REAL Auth metadata, not by row count'],
  },

  // --- roster ------------------------------------------------------------
  {
    name: 'the roster sourced from Firestore users/{uid} instead of Auth',
    file: 'src/roster.js',
    from: '  const page = await auth.listUsers(Math.min(Math.max(pageSize, 1), 1000), pageToken);',
    to:
      '  const found = await db.collection(\'users\').get();\n' +
      '  const page = { users: found.docs.map((d) => ({ uid: d.id, metadata: {} })), pageToken: null };',
    expect: [
      'THE TRAP: users/{uid} documents do not exist, and the roster works anyway',
    ],
  },
  {
    name: 'the pending-deletion flag never set',
    file: 'src/roster.js',
    from: "return [uid, snapshot.exists ? 'pending' : 'no'];",
    to: "return [uid, snapshot.exists && false ? 'pending' : 'no'];",
    expect: ['the roster flags the account'],
  },

  // --- account metadata --------------------------------------------------
  {
    name: 'the settings projection dropped (whole preferences document fetched)',
    file: 'src/account.js',
    from: "      .select('updatedAt', 'syncedAt')\n",
    to: '',
    expect: ['counts, date range, devices and settings, with no log content read'],
  },
  {
    name: 'latest-log-date query pointed the wrong way',
    file: 'src/account.js',
    from: "      edgeDate(db, uid, 'desc'),",
    to: "      edgeDate(db, uid, 'asc'),",
    expect: ['counts, date range, devices and settings, with no log content read'],
  },

  // --- decoding ----------------------------------------------------------
  {
    name: '0-valued numeric metrics rendered as readings',
    file: 'src/records.js',
    from: "      if (typeof value === 'number' && value !== 0) {",
    to: "      if (typeof value === 'number') {",
    expect: ['reserved tag prefixes are grouped and 0-valued metrics are dropped'],
  },
];

// --- the sandboxed tree ----------------------------------------------------

const copy = (from, to) => fs.cpSync(from, to, { recursive: true });

function buildSandbox(root) {
  fs.mkdirSync(path.join(root, 'admin'), { recursive: true });
  copy(path.join(ADMIN, 'src'), path.join(root, 'admin', 'src'));
  copy(path.join(ADMIN, 'test'), path.join(root, 'admin', 'test'));
  // Relative imports reaching outside admin/: the rules harness and the rules
  // file itself, both used by the "adminAudit is matched by no rule" test.
  fs.mkdirSync(path.join(root, 'firebase_test'), { recursive: true });
  fs.copyFileSync(
    path.join(REPO, 'firebase_test', 'emulator.mjs'),
    path.join(root, 'firebase_test', 'emulator.mjs'),
  );
  fs.copyFileSync(
    path.join(REPO, 'firestore.rules'),
    path.join(root, 'firestore.rules'),
  );
  fs.symlinkSync(
    path.join(ADMIN, 'node_modules'),
    path.join(root, 'admin', 'node_modules'),
    'dir',
  );
  return path.join(root, 'admin', 'test', 'admin.test.mjs');
}

function applyMutant(root, mutant) {
  const file = path.join(root, 'admin', mutant.file);
  const original = fs.readFileSync(file, 'utf8');
  const occurrences = original.split(mutant.from).length - 1;
  if (occurrences === 0) {
    throw new Error(`mutant anchor not found in ${mutant.file}: ${mutant.name}`);
  }
  if (occurrences > 1) {
    throw new Error(
      `mutant anchor is ambiguous (${occurrences} matches) in ${mutant.file}: ${mutant.name}`,
    );
  }
  fs.writeFileSync(file, original.replace(mutant.from, mutant.to));
  return () => fs.writeFileSync(file, original);
}

function failingTests(suite) {
  const run = spawnSync(process.execPath, ['--test', '--test-reporter=tap', suite], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  const output = `${run.stdout}${run.stderr}`;
  const failures = [...output.matchAll(/^\s*not ok \d+ - (.+?)\s*$/gm)].map((m) => m[1]);
  return { failures, output };
}

// --- run -------------------------------------------------------------------

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lunatrack-panel-mutants-'));
const suite = buildSandbox(tmp);
let survivors = 0;

console.log(`\nmutation check — ${MUTANTS.length} mutants\n`);

// A sanity gate: the sandbox itself must be green before any mutant means
// anything. A broken copy would make every mutant look "killed".
const baseline = failingTests(suite);
if (baseline.failures.length > 0) {
  console.error('the unmutated sandbox is not green — mutation results would be meaningless:');
  console.error(baseline.failures.join('\n'));
  console.error(baseline.output.split('\n').slice(-25).join('\n'));
  fs.rmSync(tmp, { recursive: true, force: true });
  process.exit(1);
}
console.log('  baseline: unmutated sandbox is green\n');

for (const mutant of MUTANTS) {
  const restore = applyMutant(tmp, mutant);
  const { failures, output } = failingTests(suite);
  restore();

  const missed = mutant.expect.filter((name) => !failures.includes(name));
  if (missed.length > 0) {
    survivors += 1;
    console.log(`  x SURVIVED: ${mutant.name}`);
    for (const name of missed) console.log(`      still passing: ${name}`);
    if (failures.length === 0) console.log(output.split('\n').slice(-12).join('\n'));
  } else {
    console.log(`  ok killed by ${mutant.expect.length} test(s): ${mutant.name}`);
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (survivors > 0) {
  console.error(
    `\n${survivors} mutant(s) survived: that guard is not covered by any test. ` +
      'Write the test, or delete the guard.\n',
  );
  process.exit(1);
}
console.log('\nall mutants killed — every guard in the panel is tested\n');
