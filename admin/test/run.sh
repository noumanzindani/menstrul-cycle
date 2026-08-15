#!/usr/bin/env bash
#
# Runs the operator-panel suite against LOCAL emulators.
#
#   admin/test/run.sh                # the suite
#   admin/test/run.sh --mutants      # + prove each test discriminates
#
# Nothing here contacts a remote Firebase project: the project id is
# `demo-lunatrack`, and firebase-tools treats any `demo-*` id as emulator-only
# and refuses to resolve it against production. There is deliberately no
# `.firebaserc` anywhere in this repo, so no command has a default project to
# fall into. The Firestore and Auth emulators are both local, and the Admin SDK
# picks them up from FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST,
# which `emulators:exec` exports for its child process.
#
# Requirements: Node 20+, a JDK 21+ for the emulators, and `npm install` having
# been run in `admin/` (firebase-admin + express, both pre-authorised).
set -euo pipefail

admin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "${admin}/node_modules/firebase-admin" ]]; then
  echo "admin/node_modules is missing — run: (cd admin && npm install)" >&2
  exit 1
fi

# firebase-tools 15 refuses to start the emulators on a JDK older than 21, and
# this machine's default `java` is 17.
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
  if jdk="$(/usr/libexec/java_home -v 21+ 2>/dev/null)"; then
    export JAVA_HOME="$jdk"
    export PATH="$jdk/bin:$PATH"
  fi
fi

target="node --test --test-reporter=spec ${admin}/test/admin.test.mjs"
if [[ "${1:-}" == "--mutants" ]]; then
  target="node --test --test-reporter=spec ${admin}/test/admin.test.mjs \
    && node ${admin}/test/mutants.mjs"
fi

cd "$admin"
exec firebase emulators:exec \
  --only firestore,auth \
  --project demo-lunatrack \
  --config "${admin}/firebase.json" \
  "$target"
