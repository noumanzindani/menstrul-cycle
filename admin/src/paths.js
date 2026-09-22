// The document paths the app actually uses, transcribed from the Dart source
// rather than from notes.
//
//   users/{uid}                        NEVER CREATED. `SyncService` writes only
//                                      subcollections; the sole operation on the
//                                      parent is `AccountDeletionService`'s final
//                                      `delete()`. `collection('users').get()`
//                                      therefore returns nothing, always.
//   users/{uid}/dailyLogs/{YYYY-MM-DD} SyncService._remoteLogs
//   users/{uid}/settings/current       SyncService._remoteSettings
//   users/{uid}/deletions/{YYYY-MM-DD} SyncService._remoteDeletions
//   users/{uid}/devices/{deviceId}     SyncService._deviceDoc
//   deletionRequests/{uid}             AccountDeletionService
//
// Sources: `lib/services/sync_service.dart`,
// `lib/services/account_deletion_service.dart`, `lib/services/sync_mapper.dart`.

/**
 * `kLunaDatabaseId` in `lib/services/firestore_ref.dart`.
 *
 * Exported so there is exactly ONE copy of this string in the panel. There
 * were three (`env.js`, `seed-local.mjs`, `test/support.mjs`), they drifted,
 * and the drift is invisible at runtime: a Firestore handle for a database
 * that does not exist does not throw, so the seeder wrote 142 days into
 * `lunatrack` while the panel read `lunatrack-db` and rendered a confident
 * "0 total logged days".
 */
export const LUNA_DATABASE_ID = 'lunatrack-db';

/** Mirrors `AccountDeletionService` in `lib/services/account_deletion_service.dart`. */
export const AccountDeletionService = {
  requestsCollection: 'deletionRequests',
  requestPath: (uid) => `deletionRequests/${uid}`,
  /**
   * Every subcollection under `users/{uid}`, in the order the purge sweeps
   * them. Kept in step with the Dart constant of the same name — if a new
   * subcollection is added there and not here, the account-detail view silently
   * stops reporting it.
   */
  subcollections: [
    'dailyLogs',
    'settings',
    'deletions',
    'devices',
    // Added in schema v12 (2026-09-18), when the owner reversed the
    // local-only ruling on these tables. They were absent here for a day,
    // which is exactly the silent under-reporting the doc comment above
    // warns about: the account view counted four subcollections and called
    // that the account, while four more held data.
    'reminders',
    'medications',
    'analysisSessions',
    'analysisMessages',
  ],
};

export const dailyLogsPath = (uid) => `users/${uid}/dailyLogs`;
export const settingsPath = (uid) => `users/${uid}/settings`;
export const deletionsPath = (uid) => `users/${uid}/deletions`;
export const devicesPath = (uid) => `users/${uid}/devices`;

/**
 * `FlowIntensity` from `lib/models/enums.dart`, by INDEX — which is what
 * `sync_mapper.dart`'s `dailyLogToMap` writes (`log.flow?.index`). The comment
 * on that enum says never reorder; this array depends on that promise, so an
 * out-of-range index renders as an explicit "unknown (n)" rather than silently
 * picking the wrong label.
 */
export const FLOW_INTENSITY = [
  'none',
  'spotting',
  'light',
  'medium',
  'heavy',
  'flooding',
];

export const flowLabel = (index) => {
  if (index === null || index === undefined) return null;
  return FLOW_INTENSITY[index] ?? `unknown (${index})`;
};

/** `none.isBleeding == false` — see CLAUDE.md, "Period ended". */
export const isBleeding = (index) =>
  typeof index === 'number' && index > 0 && index < FLOW_INTENSITY.length;

/**
 * Reserved key prefixes inside the `symptoms` blob
 * (`lib/common/catalog.dart`, `kReservedTagPrefixes`). Many groups ride that one
 * JSON object; the app strips these prefixes so they never reach the symptom
 * chip list. The panel groups by them instead of hiding them — the owner asked
 * for "each and everything about a user's day".
 */
export const TAG_PREFIXES = {
  sex_: 'Sexual activity',
  cm_: 'Cervical mucus',
  vag_: 'Vaginal health',
  shx_: 'Sexual health',
  habit_: 'Lifestyle habits',
  med_: 'Medication taken',
  urn_: 'Urinary',
  dig_: 'Digestion',
  skin_: 'Skin & hair',
  slf_: 'Intimacy',
  lbd_: 'Libido',
};

/**
 * Numeric day metrics (`lib/common/catalog.dart`). They ride the same blob as
 * real JSON numbers, so they never satisfy the `== true` symptom check and
 * carry no key prefix. **`0` means "unset" for every one of them, weight
 * included** — rendering a 0 as a reading would invent data.
 */
export const NUMERIC_METRICS = {
  pain: 'Pain (0–10)',
  water: 'Water (glasses)',
  sleep: 'Sleep (hours)',
  energy: 'Energy (1–5)',
  stress: 'Stress (1–5)',
  sleep_quality: 'Sleep quality (1–5)',
  weight: 'Weight (kg)',
};

/**
 * The signup sexual-health baseline, transcribed from `lib/common/catalog.dart`
 * (`kFrequencyOptions`, `kLibidoOptions`, `kSexualHistoryOptions`,
 * `kIntimacyWaysOptions`, `kSatisfactionTimeOptions`).
 *
 * This is the ONE place in the panel that names these keys. It lives in
 * `paths.js` with the other transcriptions so there is a single file to diff
 * against the Dart source when the catalog changes.
 *
 * `slfw_private` ("Prefer not to say") is decodable but is NOT in the app's
 * picker any more — it was retired on 2026-09-18 and older baselines still
 * carry it. Rendering it as an unknown key would misreport a deliberate
 * refusal to answer as data corruption, so it is listed here.
 */
export const BASELINE_LABELS = {
  frequency: {
    freq_never: 'Never',
    freq_rarely: 'Rarely',
    freq_weekly: 'Weekly',
    freq_often: 'Several times a week',
  },
  libido: {
    lbd_low: 'Low libido',
    lbd_medium: 'Medium libido',
    lbd_high: 'High libido',
  },
  history: {
    shx_none: 'None of these',
    shx_pain: 'Pain during sex',
    shx_post_coital: 'Bleeding after sex',
    vag_dryness: 'Dryness',
  },
  soloWays: {
    slfw_hands: 'Hands',
    slfw_toy: 'Toy or vibrator',
    slfw_water: 'Water',
    slfw_other: 'Other',
    slfw_private: 'Prefer not to say',
  },
  satisfactionTime: {
    sat_under5: 'Under 5 minutes',
    sat_5_15: '5-15 minutes',
    sat_15_30: '15-30 minutes',
    sat_over30: 'Over 30 minutes',
    sat_never: "Doesn't happen",
    sat_private: 'Prefer not to answer',
  },
};

/**
 * The field on `users/{uid}/settings/current` that carries the baseline, as a
 * JSON STRING rather than a map — `sync_service.dart` pushes the column
 * verbatim (`'sexualHealthBaseline': row.sexualHealthBaseline`).
 *
 * Because it is a string, Firestore cannot index into it and a security rule
 * cannot see inside it. The only access boundary on any of its contents is
 * `isOwner` on the whole document.
 */
export const BASELINE_FIELD = 'sexualHealthBaseline';

/** `syncDocId` in `lib/services/sync_mapper.dart`: the local ISO-8601 date. */
export const DATE_ID = /^\d{4}-\d{2}-\d{2}$/;
