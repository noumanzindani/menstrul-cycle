// Runtime configuration. Everything comes from the environment; nothing about
// which Firebase project this panel talks to is baked into the source.
//
// **TODO — the owning Firebase project is UNDECIDED.** See the TODO in the
// repo's `CLAUDE.md` ("Key design decisions"): `lib/services/firestore_ref.dart`
// names one project, the untracked root `firebase.json` names a different,
// unrelated one, and the owner has an open decision about moving LunaTrack to a
// dedicated project. Until that lands, a hardcoded project id here would point
// the panel at the wrong database — possibly a third party's. So there is no
// default: `LUNATRACK_PROJECT_ID` (or the Cloud Run-provided
// `GOOGLE_CLOUD_PROJECT`) MUST be set, and startup fails loudly if it is not.

/** Thrown for a configuration problem that must stop the process. */
export class ConfigError extends Error {}

const required = (value, name, why) => {
  if (value === undefined || value === null || value === '') {
    throw new ConfigError(`${name} is not set. ${why}`);
  }
  return value;
};

/**
 * Parses `ADMIN_EMAILS` into a lowercase Set.
 *
 * Lowercased on both sides of the later comparison because Google presents
 * addresses in whatever case the user typed, and a case-sensitive allowlist
 * would fail open the moment the owner signs in as `Owner@` instead of
 * `owner@` — no, it would fail CLOSED, which is merely annoying. The real
 * reason is the reverse risk: someone "fixing" that annoyance by relaxing the
 * comparison to a substring match.
 */
export function parseAdminEmails(raw) {
  const emails = String(raw ?? '')
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter((entry) => entry.length > 0);
  return new Set(emails);
}

/**
 * Reads and validates configuration, or throws.
 *
 * Fails CLOSED on every axis: no project id, no allowlist, or no IAP audience
 * and no emulator interlock all stop the process rather than starting a panel
 * that serves menstrual-health records to whoever reaches the port.
 */
export function readConfig(env = process.env) {
  const projectId = required(
    env.LUNATRACK_PROJECT_ID ?? env.GOOGLE_CLOUD_PROJECT ?? env.GCLOUD_PROJECT,
    'LUNATRACK_PROJECT_ID',
    'The owning Firebase project is a deliberate, unresolved decision — see ' +
      'the TODO in CLAUDE.md. Set it explicitly; nothing here guesses.',
  );

  // The NAMED database LunaTrack owns (`kLunaDatabaseId` in
  // `lib/services/firestore_ref.dart`). A `(default)` database carries ONE
  // ruleset for every app in the project, which is exactly why the app does not
  // use it; the panel must read the same named database or it reads nothing.
  const databaseId = env.LUNATRACK_DATABASE_ID ?? 'lunatrack';

  const adminEmails = parseAdminEmails(env.ADMIN_EMAILS);
  if (adminEmails.size === 0) {
    throw new ConfigError(
      'ADMIN_EMAILS is empty. This is the allowlist that backs up IAP; an ' +
        'empty one would mean either "nobody" or — if the check were ever ' +
        'written the other way round — "everybody". Set it.',
    );
  }

  // The emulator interlock. A development identity bypass is only honoured
  // when the process is DEMONSTRABLY pointed at a Firestore emulator, so it
  // cannot be switched on in production by an environment-variable mistake:
  // production has no `FIRESTORE_EMULATOR_HOST`.
  const emulatorHost = env.FIRESTORE_EMULATOR_HOST ?? null;
  const requestedDevIdentity = env.ADMIN_DEV_UNSAFE_IDENTITY ?? null;
  const devIdentity =
    requestedDevIdentity && emulatorHost ? requestedDevIdentity : null;
  if (requestedDevIdentity && !emulatorHost) {
    throw new ConfigError(
      'ADMIN_DEV_UNSAFE_IDENTITY is set but FIRESTORE_EMULATOR_HOST is not. ' +
        'The identity bypass exists only for local emulator work and is ' +
        'refused against a real database.',
    );
  }

  // Without a dev identity, a verified IAP assertion is the ONLY way in, and
  // verifying one requires knowing which audience to accept. An unset audience
  // would mean accepting an assertion minted for any other IAP-protected
  // service in any Google Cloud project, which is not authentication.
  const iapAudience = devIdentity
    ? null
    : required(
        env.IAP_AUDIENCE,
        'IAP_AUDIENCE',
        'The panel authenticates by verifying the IAP JWT assertion, and an ' +
          'assertion is only meaningful for the audience it was minted for. ' +
          'Format: /projects/PROJECT_NUMBER/global/backendServices/SERVICE_ID ' +
          '(load balancer) or /projects/PROJECT_NUMBER/locations/REGION/' +
          'services/SERVICE (Cloud Run direct).',
      );

  return {
    projectId,
    databaseId,
    adminEmails,
    iapAudience,
    devIdentity,
    emulatorHost,
    port: Number(env.PORT ?? 8080),
    // How many Auth accounts the dashboard will page through before it gives
    // up and reports a truncated figure. `listUsers` costs no Firestore reads
    // but does cost wall-clock time at 1000 accounts per round trip.
    maxRosterSweep: Number(env.ADMIN_MAX_ROSTER_SWEEP ?? 50000),
    pageSize: Number(env.ADMIN_PAGE_SIZE ?? 25),
  };
}
