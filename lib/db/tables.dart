import 'package:drift/drift.dart';
import '../models/enums.dart';

/// A single menstrual period (one bleed). Cycle length is DERIVED from the gap
/// between consecutive [startDate]s — never stored — so historical edits stay
/// consistent automatically.
class PeriodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()(); // null while ongoing
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One calendar day of tracking. [symptoms] is a JSON map so new symptoms can
/// be added later with zero schema migration. [bbt]/[opk] are nullable now and
/// used by the future fertility mode.
class DailyLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()(); // normalized to local midnight
  IntColumn get flow => intEnum<FlowIntensity>().nullable()();
  TextColumn get symptoms => text().withDefault(const Constant('{}'))();
  TextColumn get mood => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get bbt => real().nullable()(); // future: fertility charting
  TextColumn get opk => text().nullable()(); // future: LH test result
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date},
      ];
}

/// A day whose local log was deleted and whose deletion has not yet been
/// pushed to Firestore.
///
/// `DailyLogRepository.deleteForDate` performs a hard DELETE, which leaves a
/// deleted day indistinguishable from a day that never existed — the next pull
/// would resurrect it from the server. A tombstone records the intent.
///
/// This is a separate table rather than a `deleted` flag on `DailyLogs` on
/// purpose: a flag would require adding `where(deleted == false)` to EVERY
/// existing read path (repositories, CycleCalculator, insights, diary, PDF
/// export), and missing one silently resurfaces deleted days in a doctor's
/// report. A tombstone table leaves all existing queries untouched.
class SyncTombstones extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()(); // normalized to local midnight
  DateTimeColumn get deletedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date},
      ];
}

/// A scheduled local notification. No server — everything fires on-device.
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get type => intEnum<ReminderType>()();
  IntColumn get hour => integer()(); // 0–23, local time
  IntColumn get minute => integer()(); // 0–59
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get recurrence => text().nullable()(); // e.g. 'daily'
  TextColumn get title => text().nullable()();
  TextColumn get payload => text().nullable()();
}

/// Medication/contraception schedule (schema ships now, UI is a later phase).
class Medications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text().nullable()(); // pill / patch / ring / injection
  TextColumn get schedule => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

/// One uploaded photo or video in the standalone media timeline.
///
/// **Unlike every other table here, drift is a local REPLICA of a cloud-origin
/// record, not the origin.** An item exists only once its bytes are in Cloud
/// Storage and its metadata document is in Firestore — the media feature is
/// cloud-required, with no offline queue and no pending state. A row's
/// existence therefore means "the bytes are up there". The bytes themselves
/// cannot live in drift (a 150 MB video read whole into a `Uint8List` is an OOM
/// on the low-end devices minSdk 26 admits), which is the entire reason for the
/// asymmetry.
///
/// The UI still reads only from here, never from Firestore — the app-wide rule
/// holds. That is also what keeps the timeline pumpable in widget tests, since
/// `lunaFirestore()` throws with no initialized Firebase app.
///
/// [id] is the primary key AND the Firestore document id AND the Storage path
/// segment, so nothing ever needs a join or a lookup table. It is a
/// client-generated random 128-bit hex id (`newMediaId`), chosen BEFORE the
/// upload starts so a crash mid-upload still leaves a path the orphan sweep can
/// reconstruct. It is never the original filename: object paths reach Cloud
/// Logging and billing exports, and "IMG_ultrasound_12wk.heic" is health data
/// in a log line.
///
/// [kind] is TEXT, not `intEnum`. `DailyLogs.flow` uses `intEnum` and puts the
/// raw index on the wire, which is survivable for a closed enum written years
/// ago; a new wire format keyed on Dart declaration order is a landmine.
///
/// [thumbnail] is a RENDER CACHE, never a source of truth — it is always
/// re-derivable by downloading [thumbPath]. It lives inside the DB rather than
/// on disk so that the only decoded bodily imagery at rest is inside the
/// sqlite3mc-encrypted store, and so `deleteAllData()` erases it for free.
class MediaItems extends Table {
  TextColumn get id => text()();
  // The account these bytes belong to. `DailyLogs` needs no such column — signing
  // out never wipes the device, and pre-existing local logs are offered to the
  // new account through the claim-consent sheet, because a log written offline
  // is genuinely the user's to keep.
  //
  // Media has no equivalent: it is cloud-required, so a row only ever exists
  // because it was uploaded under ONE uid, and its [storagePath] embeds that uid
  // — read it back while signed in as somebody else and the rules deny it, which
  // renders as a permanently broken tile. Worse, the cached [thumbnail] would
  // show account A's imagery inside account B's timeline.
  //
  // Sign-out is not the only guard here (`MediaSyncService` clears rows on a uid
  // change) but it is the one that cannot be forgotten: every read filters on
  // this column, so a missed wipe degrades to stale rows on disk rather than to
  // one user seeing another user's photographs.
  TextColumn get uid => text()();
  TextColumn get kind => text()(); // 'image' | 'video'
  TextColumn get storagePath => text()();
  TextColumn get thumbPath => text().nullable()(); // null for video in v1
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()(); // video only
  TextColumn get caption => text().nullable()();
  // The timeline's sort key. A photo taken in March and uploaded in August
  // belongs in March, so this is the capture time where the picker supplies
  // one, falling back to the upload time where it does not.
  DateTimeColumn get capturedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BlobColumn get thumbnail => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row app settings (always id = 0). Kept in the DB (not SharedPreferences)
/// so that, once encryption is enabled, even preferences stay inside the
/// encrypted store.
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  IntColumn get mode =>
      intEnum<TrackingMode>().withDefault(Constant(TrackingMode.track.index))();
  IntColumn get defaultCycleLength => integer().withDefault(const Constant(28))();
  IntColumn get defaultPeriodLength => integer().withDefault(const Constant(5))();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  TextColumn get language => text().withDefault(const Constant('en'))();
  BoolColumn get genderNeutralLanguage =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get appLockEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get premium => boolean().withDefault(const Constant(false))();
  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastBackup => dateTime().nullable()();
  // Pregnancy mode: the last-menstrual-period date the pregnancy is dated from
  // (null unless mode == pregnancy). Due date is DERIVED (Naegele), not stored.
  DateTimeColumn get pregnancyStartDate => dateTime().nullable()();
  // Enabled day-editor categories as a JSON array of ids (see
  // common/tracking_categories.dart). NULL means "use defaults", so existing
  // rows need no backfill.
  TextColumn get trackingCategories => text().nullable()();
  // Weight display unit ('kg' | 'lb'). NULL means "never chosen" and reads as
  // kg. Weight VALUES are always stored in canonical kg in the day-tags blob,
  // so switching this never rewrites data.
  TextColumn get weightUnit => text().nullable()();
  // High-water mark for Firestore sync: rows with `updatedAt` after this need
  // pushing, remote docs after this need pulling. NULL means "never synced",
  // which correctly triggers a full initial pull.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  // When the settings row itself last changed. `DailyLogs` already has its own
  // `updatedAt`; settings had none, and without it sync cannot tell a locally
  // edited preference from a stale one — so a device syncing later would push
  // its old settings over another device's newer change.
  DateTimeColumn get settingsUpdatedAt => dateTime().nullable()();
  // Which account opted in to sending a photo to Google for description.
  //
  // The UID, not a bool, and that is the point: a device-global flag would let
  // account B's photos be described on account A's consent, which is the exact
  // bug `ClaimPreference` records for the sync decision. NULL means no account
  // on this device has opted in; a value that is not the current uid reads as
  // "not consented" without needing to be cleared on sign-out.
  //
  // Deliberately NOT synced (see SyncService._pushSettings): consent to send
  // bytes to a third party is a per-device decision, and pushing it would opt a
  // user's other phone in to something they agreed to on this one.
  TextColumn get analysisConsentUid => text().nullable()();
  // Daily-cap bookkeeping for photo descriptions: the local `yyyy-mm-dd` the
  // count belongs to, and the count itself. A stored day that is not today
  // reads as zero (see `analysisCountForDay`), so the counter rolls over with
  // no midnight timer and no cleanup pass. NULL on both = never used.
  TextColumn get analysisCountDay => text().nullable()();
  IntColumn get analysisCountToday => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
