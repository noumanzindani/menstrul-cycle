#!/usr/bin/env bash
#
# Runs the account-deletion PURGE tests against LOCAL emulators.
#
#   firebase_test/purge_run.sh              # the suite
#   firebase_test/purge_run.sh --mutants    # + prove each test discriminates
#
# Sibling of `run.sh`, which covers `firestore.rules`. This one is separate
# because the purge deletes Firebase Auth users, so it needs the AUTH emulator
# as well — configured in `firebase_test/purge.firebase.json` rather than in the
# repo-root `firebase.json`, which is left byte-identical.
#
# Nothing here contacts a remote Firebase project: the project id is
# `demo-lunatrack`, and firebase-tools treats any `demo-*` id as emulator-only
# and refuses to resolve it against production. There is deliberately no
# `.firebaserc`, so no command in this repo has a default project to fall into.
# No project id appears in any committed file — the deployable function takes it
# from the ambient environment (see `functions/index.js`).
#
# Requirements: Node 18+ (built-in test runner), a JDK 21+ for the Firestore
# emulator, and `npm ci` having been run once in `functions/` (the purge runs on
# the Admin SDK, so its own suite needs it too).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "${repo}/functions/node_modules/firebase-admin" ]]; then
  echo "functions/node_modules is missing — run:  (cd functions && npm ci)" >&2
  exit 1
fi

# firebase-tools 15 refuses to start the emulator on a JDK older than 21, and
# this machine's default `java` is 17. Prefer a 21+ JVM if `java_home` knows one.
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
  if jdk="$(/usr/libexec/java_home -v 21+ 2>/dev/null)"; then
    export JAVA_HOME="$jdk"
    export PATH="$jdk/bin:$PATH"
  fi
fi

target="node --test --test-reporter=spec ${repo}/firebase_test/purge.test.mjs"
if [[ "${1:-}" == "--mutants" ]]; then
  target="node --test --test-reporter=spec ${repo}/firebase_test/purge.test.mjs \
    && node ${repo}/firebase_test/purge_mutation_check.mjs"
fi

cd "$repo"
exec firebase emulators:exec \
  --config firebase_test/purge.firebase.json \
  --only firestore,auth \
  --project demo-lunatrack \
  "$target"
