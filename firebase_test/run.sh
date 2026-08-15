#!/usr/bin/env bash
#
# Runs the Firestore rules tests against a LOCAL emulator.
#
#   firebase_test/run.sh                  # the suite
#   firebase_test/run.sh --mutants        # + prove each test discriminates
#
# Nothing here contacts a remote Firebase project: the project id is
# `demo-lunatrack`, and firebase-tools treats any `demo-*` id as emulator-only
# and refuses to resolve it against production. There is deliberately no
# `.firebaserc`, so no command in this repo has a default project to fall into.
#
# Requirements: Node 18+ (built-in fetch and test runner) and a JDK 21+ for the
# Firestore emulator. No npm packages — see the header of `emulator.mjs`.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# firebase-tools 15 refuses to start the emulator on a JDK older than 21, and
# this machine's default `java` is 17. Prefer a 21+ JVM if `java_home` knows one.
if command -v /usr/libexec/java_home >/dev/null 2>&1; then
  if jdk="$(/usr/libexec/java_home -v 21+ 2>/dev/null)"; then
    export JAVA_HOME="$jdk"
    export PATH="$jdk/bin:$PATH"
  fi
fi

target="node --test --test-reporter=spec ${repo}/firebase_test/rules.test.mjs"
if [[ "${1:-}" == "--mutants" ]]; then
  target="node --test --test-reporter=spec ${repo}/firebase_test/rules.test.mjs \
    && node ${repo}/firebase_test/mutation_check.mjs"
fi

cd "$repo"
exec firebase emulators:exec \
  --only firestore \
  --project demo-lunatrack \
  "$target"
