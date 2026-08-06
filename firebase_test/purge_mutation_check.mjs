// Proves that `purge.test.mjs` actually discriminates.
//
// A test that passes with its own fix reverted is worthless, and this project
// has shipped several. So rather than trusting that each assertion is
// load-bearing, this re-runs the WHOLE purge suite once per mutant —
// `functions/purge.js` with exactly one guarantee removed — and fails unless the
// named test goes red.
//
// A "surviving" mutant means the behaviour it breaks is not covered by any test:
// either write the test, or delete the code. `redundant: true` marks a mutant
// that is deliberately expected to survive, and documents why.
//
// The same shape as `mutation_check.mjs` (which does this for `firestore.rules`)
// and it runs inside `firebase emulators:exec`, same as the suite itself.
//
// `purge.js` deliberately requires nothing but Node built-ins, so a mutated copy
// alone in a temp directory loads and runs exactly like the original.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const PURGE_PATH = path.join(here, '..', 'functions', 'purge.js');
const WIRING_PATH = path.join(here, '..', 'functions', 'index.js');
const SUITE = path.join(here, 'purge.test.mjs');
const ORIGINAL = fs.readFileSync(PURGE_PATH, 'utf8');
const ORIGINAL_WIRING = fs.readFileSync(WIRING_PATH, 'utf8');

/**
 * Each mutant removes ONE guarantee and names the test(s) that must go red.
 *
 * `from` is matched literally against `purge.js`; a mutant whose anchor no
 * longer exists is a hard failure, so this file cannot silently rot as the
 * implementation is edited.
 */
const MUTANTS = [
  // --- the server-side re-derivation --------------------------------------
  {
    name: 'the requestedAt + graceWindow re-derivation dropped (purgeAfter trusted)',
    from: 'if (dueAt.getTime() > at.getTime()) {',
    to: 'if (false) {',
    expect: [
      'a purgeAfter that disagrees with requestedAt + graceWindow does not purge early',
    ],
  },
  {
    name: 'the unverifiable-requestedAt guard dropped',
    from: 'if (requestedAt === null) {',
    to: 'if (false) {',
    expect: [
      'a marker with no requestedAt is never purged',
      'a requestedAt of the wrong type is never purged',
    ],
  },
  {
    name: 'the grace window collapsed to zero days',
    from: 'const GRACE_WINDOW_DAYS = 30;',
    to: 'const GRACE_WINDOW_DAYS = 0;',
    expect: [
      'the grace window matches AccountDeletionService.graceWindow',
      'a purgeAfter that disagrees with requestedAt + graceWindow does not purge early',
    ],
  },
  {
    name: 'the deadline boundary made exclusive (>= instead of >)',
    from: 'if (dueAt.getTime() > at.getTime()) {',
    to: 'if (dueAt.getTime() >= at.getTime()) {',
    expect: ['a marker exactly at requestedAt + graceWindow is due'],
  },
  {
    name: 'the document id replaced by the client-written uid field',
    from: 'const uid = marker.id;',
    to: "const uid = marker.get('uid');",
    expect: [
      'the document id decides whose account is purged, not the uid field',
    ],
  },

  // --- the queue query -----------------------------------------------------
  {
    name: 'the purgeAfter filter dropped (every marker collected)',
    from: ".where('purgeAfter', '<=', at)",
    to: '',
    expect: ['a marker still inside the grace window is not collected at all'],
  },
  {
    name: 'the per-invocation limit ignored',
    from: '.limit(limit)',
    to: '.limit(1000)',
    expect: ['the sweep is limited, and takes the oldest deadlines first'],
  },
  {
    name: 'the queue ordered newest-deadline-first',
    from: ".orderBy('purgeAfter')",
    to: ".orderBy('purgeAfter', 'desc')",
    expect: ['the sweep is limited, and takes the oldest deadlines first'],
  },
  {
    name: 'the found count faked',
    from: 'found: queue.size,',
    to: 'found: 0,',
    expect: [
      'a clean sweep logs found / purged / skipped / failed counts',
      'the sweep is limited, and takes the oldest deadlines first',
      're-running after a crash finishes the job',
    ],
  },

  // --- the subtree sweep ---------------------------------------------------
  {
    name: 'the subcollection list truncated to dailyLogs',
    from: "const SUBCOLLECTIONS = ['dailyLogs', 'settings', 'deletions', 'devices'];",
    to: "const SUBCOLLECTIONS = ['dailyLogs'];",
    expect: [
      'the subcollection list matches AccountDeletionService.subcollections',
      'every subcollection the Dart spec names is emptied',
      'a marker past its deadline erases the whole account',
    ],
  },
  {
    name: 'the root users/{uid} document left behind',
    from: 'await firestore.doc(`users/${uid}`).delete();',
    to: '',
    expect: [
      'the root users/{uid} document is deleted',
      'a marker past its deadline erases the whole account',
    ],
  },
  {
    name: 'the root document deleted FIRST, before the subcollections',
    from: '  for (const name of SUBCOLLECTIONS) {',
    to:
      '  await firestore.doc(`users/${uid}`).delete();\n' +
      '  for (const name of SUBCOLLECTIONS) {',
    expect: [
      'a crash mid-sweep leaves the root document, the marker and the Auth user',
    ],
  },
  {
    name: 'subcollection paging reduced to a single page',
    from: '      if (page.empty) break;',
    to: '      if (page.empty) break;\n      if (true) { const w = firestore.batch(); for (const d of page.docs) w.delete(d.ref); await w.commit(); break; }',
    expect: ['a subcollection larger than one page is fully emptied'],
  },

  // --- Auth ----------------------------------------------------------------
  {
    name: 'the Firebase Auth account never deleted',
    from: 'await deleteAuthAccount(deleteAuthUser, uid);',
    to: '',
    expect: [
      'the Firebase Auth account is deleted',
      'a marker past its deadline erases the whole account',
      'a failure deleting the Auth user leaves the marker for the next run',
    ],
  },
  {
    name: 'the already-deleted Auth user treated as an error',
    from: "if (error && error.code === 'auth/user-not-found') return;",
    to: '',
    expect: ['an account whose Auth user is already gone still purges'],
  },

  // --- the marker, and the ordering that makes the job resumable -----------
  {
    name: 'the marker never deleted',
    from: 'await marker.ref.delete();',
    to: '',
    expect: [
      'the marker itself is deleted — the Dart sweep does not do it',
      're-running over an already-purged account does nothing',
      'a marker past its deadline erases the whole account',
    ],
  },
  {
    name: 'the marker deleted FIRST, before any data (queue entry lost on crash)',
    from: '      await deleteFirestoreData(firestore, uid);',
    to: '      await marker.ref.delete();\n      await deleteFirestoreData(firestore, uid);',
    expect: [
      'a crash mid-sweep leaves the root document, the marker and the Auth user',
      'a failure deleting the Auth user leaves the marker for the next run',
      'one account failing does not stop the others',
    ],
  },
  {
    name: 'the marker deleted BEFORE the Auth account',
    from: '      await deleteAuthAccount(deleteAuthUser, uid);\n      await marker.ref.delete();',
    to: '      await marker.ref.delete();\n      await deleteAuthAccount(deleteAuthUser, uid);',
    expect: [
      'a failure deleting the Auth user leaves the marker for the next run',
    ],
  },

  // --- error handling ------------------------------------------------------
  {
    name: 'failures swallowed silently',
    from: '      summary.failed.push({\n        account,\n        reason: redactUid(error && error.message, uid),\n      });',
    to: '',
    expect: [
      'a failure deleting the Auth user leaves the marker for the next run',
      'one account failing does not stop the others',
      'an error message quoting the uid is redacted before it is logged',
      'a sweep with failures logs the counts and the failure reason',
    ],
  },
  {
    name: 'one account\'s failure aborts the whole sweep',
    from: '    } catch (error) {',
    to: '    } catch (error) {\n      throw error; // eslint-disable-line',
    expect: [
      'one account failing does not stop the others',
      'a failure deleting the Auth user leaves the marker for the next run',
    ],
  },

  // --- logging hygiene -----------------------------------------------------
  {
    name: 'the uid logged in plaintext instead of a hash',
    from: "createHash('sha256').update(String(uid)).digest('hex').slice(0, 12);",
    to: 'String(uid);',
    expect: ['logs never carry a plaintext uid or anything from a document body'],
  },
  {
    name: 'error messages logged without redacting the uid',
    from: '  return text.split(String(uid)).join(`<account:${accountLabel(uid)}>`);',
    to: '  return text;',
    expect: ['an error message quoting the uid is redacted before it is logged'],
  },
  {
    name: 'a clean sweep logs nothing',
    from: "    logger.info('account purge finished', counts);",
    to: '',
    expect: ['a clean sweep logs found / purged / skipped / failed counts'],
  },
  {
    name: 'a sweep with skips logs nothing',
    from: "    logger.warn('account purge finished with skips', {\n      ...counts,\n      skips: summary.skipped,\n    });",
    to: '',
    expect: ['a sweep with skips logs the counts and the skip reason'],
  },
  {
    name: 'the skip reason dropped from the log',
    from: "    logger.warn('account purge finished with skips', {\n      ...counts,\n      skips: summary.skipped,\n    });",
    to: "    logger.warn('account purge finished with skips', counts);",
    expect: ['a sweep with skips logs the counts and the skip reason'],
  },
  {
    name: 'a sweep with failures logs nothing',
    from: "    logger.error('account purge finished with failures', {\n      ...counts,\n      failures: summary.failed,\n      skips: summary.skipped,\n    });",
    to: '',
    expect: ['a sweep with failures logs the counts and the failure reason'],
  },
  {
    name: 'the failure reason dropped from the log',
    from: "    logger.error('account purge finished with failures', {\n      ...counts,\n      failures: summary.failed,\n      skips: summary.skipped,\n    });",
    to: "    logger.error('account purge finished with failures', counts);",
    expect: ['a sweep with failures logs the counts and the failure reason'],
  },

  // --- the queue collection name ------------------------------------------
  {
    name: 'the work queue pointed at the wrong collection',
    from: "const REQUESTS_COLLECTION = 'deletionRequests';",
    to: "const REQUESTS_COLLECTION = 'purgeQueue';",
    expect: [
      'the queue collection matches AccountDeletionService.requestsCollection',
      'a marker past its deadline erases the whole account',
    ],
  },
];

/**
 * Mutants of `functions/index.js` — the deployable wiring.
 *
 * Configuration is the one part of this feature the emulator suite cannot
 * execute (a scheduled trigger has no local runtime), so it is covered
 * structurally instead. That coverage is only worth anything if it discriminates,
 * hence these.
 */
const WIRING_MUTANTS = [
  {
    name: 'the Firestore handle pointed at the (default) database',
    from: 'getFirestore(app, LUNA_DATABASE_ID)',
    to: 'getFirestore(app)',
    expect: ['the deployable wiring targets the NAMED lunatrack database'],
  },
  {
    name: 'the named database id changed out from under the app',
    from: "const LUNA_DATABASE_ID = 'lunatrack';",
    to: "const LUNA_DATABASE_ID = 'default';",
    expect: ['the deployable wiring targets the NAMED lunatrack database'],
  },
  {
    name: 'a real project id pinned in the deployable wiring',
    from: 'const app = initializeApp();',
    to: "const app = initializeApp({ projectId: 'ride-with-purpose' });",
    expect: ['no Firebase project id is hardcoded in functions/ or in this suite'],
  },
];

function mutate(mutant, original, where) {
  const occurrences = original.split(mutant.from).length - 1;
  if (occurrences === 0) {
    throw new Error(`mutant anchor not found in ${where}: ${mutant.name}`);
  }
  if (occurrences > 1 && !mutant.all) {
    throw new Error(
      `mutant anchor is ambiguous (${occurrences} matches): ${mutant.name}`,
    );
  }
  return mutant.all
    ? original.split(mutant.from).join(mutant.to)
    : original.replace(mutant.from, mutant.to);
}

/** Runs the suite with [env] applied and returns the names that failed. */
function failingTests(env) {
  const run = spawnSync(
    process.execPath,
    ['--test', '--test-reporter=tap', SUITE],
    { env: { ...process.env, ...env }, encoding: 'utf8' },
  );
  const output = `${run.stdout}${run.stderr}`;
  const failures = [...output.matchAll(/^\s*not ok \d+ - (.+?)\s*$/gm)].map(
    (match) => match[1],
  );
  return { failures, output };
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lunatrack-purge-mutants-'));
let survivors = 0;

const all = [
  ...MUTANTS.map((mutant) => ({
    mutant,
    original: ORIGINAL,
    where: 'purge.js',
    variable: 'LUNA_PURGE_MODULE',
  })),
  ...WIRING_MUTANTS.map((mutant) => ({
    mutant,
    original: ORIGINAL_WIRING,
    where: 'index.js',
    variable: 'LUNA_WIRING_FILE',
  })),
];

console.log(`\nmutation check — ${all.length} mutants\n`);

for (const { mutant, original, where, variable } of all) {
  const file = path.join(tmp, `${mutant.name.replace(/\W+/g, '-')}.js`);
  fs.writeFileSync(file, mutate(mutant, original, where));
  const { failures, output } = failingTests({ [variable]: file });

  if (mutant.redundant) {
    const status = failures.length === 0 ? 'REDUNDANT (as documented)' : 'covered';
    console.log(`  ~ ${mutant.name}\n      ${status}: ${mutant.redundant}`);
    continue;
  }

  const missed = mutant.expect.filter((name) => !failures.includes(name));
  if (missed.length > 0) {
    survivors += 1;
    console.log(`  ✗ SURVIVED: ${mutant.name}`);
    for (const name of missed) console.log(`      still passing: ${name}`);
    if (failures.length === 0) {
      console.log(output.split('\n').slice(-14).join('\n'));
    }
  } else {
    console.log(`  ✓ killed by ${mutant.expect.length} test(s): ${mutant.name}`);
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (survivors > 0) {
  console.error(
    `\n${survivors} mutant(s) survived: that behaviour is not covered by any ` +
      `test. Write the test, or delete the code.\n`,
  );
  process.exit(1);
}
console.log(
  '\nall mutants killed — every guarantee in purge.js and index.js is tested\n',
);
