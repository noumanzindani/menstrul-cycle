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
  subcollections: ['dailyLogs', 'settings', 'deletions', 'devices'],
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

/** `syncDocId` in `lib/services/sync_mapper.dart`: the local ISO-8601 date. */
export const DATE_ID = /^\d{4}-\d{2}-\d{2}$/;
