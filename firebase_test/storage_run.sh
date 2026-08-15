#!/usr/bin/env bash
#
# Runs the Cloud Storage rules tests against a LOCAL emulator.
#
#   firebase_test/storage_run.sh
#
# Nothing here contacts a remote Firebase project: the project id is
# `demo-lunatrack`, and firebase-tools treats any `demo-*` id as emulator-only
# and refuses to resolve it against production. There is deliberately no
# `.firebaserc`, so no command in this repo has a default project to fall into.
#
# Requirements: Node 18+ (built-in fetch and test runner) and a JDK 21+. No npm
# packages — see the header of `storage_emulator.mjs`.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# firebase-tools refuses to start the emulator on a JDK older than 21, and this
# machine's default `java` may be older. Prefer a 21+ JVM if `java_home` knows
# one. Same shim as `run.sh`.
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
  if jdk="$(/usr/libexec/java_home -v 21+ 2>/dev/null)"; then
    export JAVA_HOME="$jdk"
    export PATH="$jdk/bin:$PATH"
  fi
fi

cd "$repo"
exec firebase emulators:exec \
  --only storage \
  --project demo-lunatrack \
  "node --test --test-reporter=spec ${repo}/firebase_test/storage.test.mjs"
