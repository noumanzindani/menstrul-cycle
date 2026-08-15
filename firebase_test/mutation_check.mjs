// Proves that `rules.test.mjs` actually discriminates.
//
// A rules test that passes against permissive rules is worthless, and this
// project has shipped tests that passed with their own fix reverted. So rather
// than trusting that each assertion is load-bearing, this re-runs the WHOLE
// suite once per mutant — `firestore.rules` with exactly one guard removed —
// and fails unless the named test goes red.
//
// A "surviving" mutant means the clause it removes is not covered by any test:
// either write the test, or delete the clause. `redundant: true` marks the one
// case where a clause is deliberately kept despite being unreachable, and
// documents why.
//
// Runs inside `firebase emulators:exec`, same as the suite itself.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.join(here, '..', 'firestore.rules');
const SUITE = path.join(here, 'rules.test.mjs');
const ORIGINAL = fs.readFileSync(RULES_PATH, 'utf8');

/**
 * Each mutant removes ONE guard and names the test(s) that must go red.
 *
 * `from` is matched literally against `firestore.rules`; a mutant whose anchor
 * no longer exists is a hard failure, so this file cannot silently rot as the
 * rules are edited.
 */
const MUTANTS = [
  {
    name: 'isOwner() degraded to "any signed-in user"',
    from: 'return request.auth != null && request.auth.uid == userId;',
    to: 'return request.auth != null;',
    expect: [
      'another signed-in user CANNOT read a day log',
      'another signed-in user CANNOT write a day log',
      'another signed-in user CANNOT record a request against someone else',
    ],
  },
  {
    name: 'isOwner() degraded to "anyone at all"',
    from: 'return request.auth != null && request.auth.uid == userId;',
    to: 'return true;',
    expect: [
      'an unauthenticated client can read nothing',
      'an unauthenticated client can write nothing',
    ],
  },
  {
    name: 'users/{uid} subtree opened to any signed-in user',
    from: 'allow read, write: if isOwner(userId);',
    to: 'allow read, write: if request.auth != null;',
    all: true,
    expect: [
      'another signed-in user CANNOT read a day log',
      'another signed-in user CANNOT list a day-log collection',
      'another signed-in user CANNOT write a day log',
      'another signed-in user CANNOT delete a day log',
      'settings/current is protected by the same identity rule',
      'the deletions markers are protected by the same identity rule',
      'the per-device pull cursors are protected by the same identity rule',
      'another signed-in user CANNOT touch the users/{uid} document',
      'nobody can enumerate the users collection',
    ],
  },
  {
    // `allow list: if isOwner(userId)` would NOT be a meaningful mutant: on a
    // whole-collection list the `{userId}` wildcard is unbound, so that
    // expression is unevaluatable and the emulator denies anyway. Only a
    // condition independent of the wildcard actually opens the collection,
    // which is the shape a well-meaning "let users see their own request"
    // edit would take.
    name: 'deletionRequests made listable by any signed-in user',
    from: 'allow list: if false;',
    to: 'allow list: if request.auth != null;',
    expect: ['the collection can NEVER be listed, not even by an owner'],
  },
  {
    name: 'deletionRequests made updatable by its owner',
    from: 'allow update: if false;',
    to: 'allow update: if isOwner(userId);',
    expect: ['an existing request cannot be overwritten'],
  },
  {
    name: 'the create-only !exists() guard dropped from the write fallback',
    from: '&& !exists(/databases/$(database)/documents/deletionRequests/$(userId));',
    to: ';',
    expect: ['an existing request cannot be overwritten'],
  },
  {
    name: 'deletionRequests get opened to any signed-in user',
    from: 'allow get: if isOwner(userId);',
    to: 'allow get: if request.auth != null;',
    expect: ['another signed-in user CANNOT read a deletion request'],
  },
  {
    name: 'deletionRequests delete opened to any signed-in user',
    from: 'allow delete: if isOwner(userId);',
    to: 'allow delete: if request.auth != null;',
    expect: [
      'the owner can cancel a pending request, twice, and a stranger cannot',
    ],
  },
  {
    name: 'deletionRequests create opened to any signed-in user',
    from: 'allow create: if isOwner(userId) && validRequest(userId);',
    to: 'allow create: if request.auth != null && validRequest(userId);',
    expect: [
      'another signed-in user CANNOT record a request against someone else',
    ],
  },
  {
    name: 'hasOnly() dropped (extra fields allowed)',
    from: "&& request.resource.data.keys().hasOnly(['uid', 'requestedAt', 'purgeAfter'])",
    to: '&& true',
    expect: ['a request carrying an extra field is refused'],
  },
  {
    name: 'the uid/path agreement check dropped',
    from: '&& request.resource.data.uid == uid',
    to: '&& true',
    expect: ['a request whose uid does not match its path is refused'],
  },
  {
    name: 'the server-stamped requestedAt check dropped',
    from: '&& request.resource.data.requestedAt == request.time',
    to: '&& true',
    expect: ['a client-chosen requestedAt is refused'],
  },
  {
    name: 'the purgeAfter lower bound dropped',
    from: "&& request.resource.data.purgeAfter > request.time + duration.value(29, 'd')",
    to: '&& true',
    expect: ['a purgeAfter in the past is refused'],
  },
  {
    name: 'the purgeAfter upper bound dropped',
    from: "&& request.resource.data.purgeAfter < request.time + duration.value(31, 'd')",
    to: '&& true',
    expect: ['a purgeAfter far in the future is refused'],
  },
  {
    name: 'a permissive catch-all match added',
    from: '  match /databases/{database}/documents {',
    to:
      '  match /databases/{database}/documents {\n' +
      '    match /{anything=**} { allow read, write: if request.auth != null; }',
    expect: [
      'an unrelated top-level collection is denied by default',
      // The catch-all is what a collection-group harvest needs: a recursive
      // wildcard rooted at the database root. `/users/{userId}/{document=**}`
      // never authorises one, however permissive its condition, so this is the
      // mutant that proves the collection-group assertion is real.
      "a collection-group query cannot harvest everyone's day logs",
      'the collection can NEVER be listed, not even by an owner',
    ],
  },
  // --- deliberately redundant clauses ------------------------------------
  {
    name: 'hasAll() dropped (partial markers allowed)',
    from: "&& request.resource.data.keys().hasAll(['uid', 'requestedAt', 'purgeAfter'])",
    to: '&& true',
    expect: [],
    redundant:
      'a missing field is already denied because reading an absent key from ' +
      'request.resource.data is an evaluation error; hasAll states the ' +
      'contract explicitly instead of relying on that side effect.',
  },
  {
    name: 'the "purgeAfter is timestamp" type check dropped',
    from: '&& request.resource.data.purgeAfter is timestamp',
    to: '&& true',
    expect: [],
    redundant:
      'comparing a non-timestamp against request.time is itself an evaluation ' +
      'error, so the bounds already reject it; the type check names the ' +
      'requirement rather than leaving it implicit.',
  },
];

function mutate(mutant) {
  const occurrences = ORIGINAL.split(mutant.from).length - 1;
  if (occurrences === 0) {
    throw new Error(`mutant anchor not found in firestore.rules: ${mutant.name}`);
  }
  if (occurrences > 1 && !mutant.all) {
    throw new Error(
      `mutant anchor is ambiguous (${occurrences} matches): ${mutant.name}`,
    );
  }
  return mutant.all
    ? ORIGINAL.split(mutant.from).join(mutant.to)
    : ORIGINAL.replace(mutant.from, mutant.to);
}

/** Runs the suite against [rulesFile] and returns the names that failed. */
function failingTests(rulesFile) {
  const run = spawnSync(
    process.execPath,
    ['--test', '--test-reporter=tap', SUITE],
    { env: { ...process.env, LUNA_RULES_FILE: rulesFile }, encoding: 'utf8' },
  );
  const output = `${run.stdout}${run.stderr}`;
  const failures = [...output.matchAll(/^\s*not ok \d+ - (.+?)\s*$/gm)].map(
    (match) => match[1],
  );
  return { failures, output };
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lunatrack-rules-mutants-'));
let survivors = 0;

console.log(`\nmutation check — ${MUTANTS.length} mutants\n`);

for (const mutant of MUTANTS) {
  const file = path.join(tmp, `${mutant.name.replace(/\W+/g, '-')}.rules`);
  fs.writeFileSync(file, mutate(mutant));
  const { failures, output } = failingTests(file);

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
      console.log(output.split('\n').slice(-12).join('\n'));
    }
  } else {
    console.log(
      `  ✓ killed by ${mutant.expect.length} test(s): ${mutant.name}`,
    );
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (survivors > 0) {
  console.error(
    `\n${survivors} mutant(s) survived: those rules are not covered by any ` +
      `test. Write the test, or delete the rule.\n`,
  );
  process.exit(1);
}
console.log('\nall mutants killed — every guard in firestore.rules is tested\n');
