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

  /// A stable identifier this row keeps on every device.
  ///
  /// [id] is `autoIncrement`, i.e. a LOCAL rowid: device A's row 3 and device
  /// B's row 3 are different reminders, so syncing on it would merge unrelated rows
  /// into each other. Nullable because the v11 -> v12 migration is additive and
  /// backfills nothing; the sync push assigns one to any row still missing it,
  /// which is where generating a uuid is natural.
  TextColumn get syncId => text().nullable()();

  /// Last local edit, for `decideMerge`'s last-write-wins. Null on a row
  /// written before v12 and never touched since -- which loses to any remote
  /// copy, the safe direction for a row this device cannot date.
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Medication/contraception schedule (schema ships now, UI is a later phase).
class Medications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text().nullable()(); // pill / patch / ring / injection
  TextColumn get schedule => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// A stable identifier this row keeps on every device.
  ///
  /// [id] is `autoIncrement`, i.e. a LOCAL rowid: device A's row 3 and device
  /// B's row 3 are different medications, so syncing on it would merge unrelated rows
  /// into each other. Nullable because the v11 -> v12 migration is additive and
  /// backfills nothing; the sync push assigns one to any row still missing it,
  /// which is where generating a uuid is natural.
  TextColumn get syncId => text().nullable()();

  /// Last local edit, for `decideMerge`'s last-write-wins. Null on a row
  /// written before v12 and never touched since -- which loses to any remote
  /// copy, the safe direction for a row this device cannot date.
  DateTimeColumn get updatedAt => dateTime().nullable()();
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

/// One saved assistant conversation.
///
/// The original design kept transcripts in memory precisely so they would need
/// no erasure path (media_analysis_service.dart:49-61). Persisting them means
/// owning all four: deleteAllData, the sign-out wipe, the .lunabak exclusion and
/// the doctor-PDF exclusion. See D9 in the spec.
///
/// Synced to Firestore (`users/{uid}/analysisSessions`) since v12 — the
/// "local-only" note that used to sit here was stale. A deletion is therefore a
/// tombstone ([deletedAt]), not a hard delete: a vanished row cannot tell other
/// devices it is gone.
class AnalysisSessions extends Table {
  TextColumn get id => text()();
  /// Scopes every read, exactly as `MediaItems.uid` does. Signing out does not
  /// wipe the device, so without this filter one account's conversation about
  /// their own body could render under another account.
  TextColumn get uid => text()();
  /// The photo this conversation started from (Describe), or `''` for one
  /// started in the Assistant tab. Stays NOT NULL so v15 devices, which read
  /// it as required, keep accepting synced rows.
  TextColumn get mediaId => text()();
  /// Which consent disclosure this conversation was created under. Stamped so a
  /// stored transcript records what the user was actually told when it started.
  IntColumn get consentVersion => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  /// The first thing the user typed, cut to 60 characters (v16). Null for a
  /// Describe chat and for every conversation from before v16.
  TextColumn get title => text().nullable()();
  /// When the user deleted this conversation (v16). Non-null rows are
  /// tombstones: hidden from every read, kept only so the next sync can carry
  /// the deletion to other devices. Their messages are already gone.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One turn in a saved conversation.
///
/// Holds the text plus, since v16, REFERENCES to what was attached
/// ([attachmentsJson]) — never the bytes, never a URL. The images themselves
/// are loaded from the media store and attached at request-build time.
///
/// Errors and refusals are rendered in the sheet but never stored: a replayed
/// transcript must reach the model identically to a live one. The one stored
/// exception, the declined-video pair, is stored with [includeInModel] false
/// for exactly that reason.
class AnalysisMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get role => text()(); // 'user' | 'model'
  // Named `messageText`, not `text`, and NOT `.named('text')` either.
  //
  // A getter called `text` in a class that extends `Table` collides with the
  // inherited `Table.text()` DSL method: Dart cannot resolve `text()` inside
  // its own initializer once `text` is redeclared as a getter (it becomes a
  // recursive, non-callable reference), and it breaks every OTHER `text()()`
  // column in this class too. `.named('text')` looked like a fix — it keeps
  // the Dart getter as `messageText` while forcing the underlying SQL column
  // name back to `text` — but it only moves the collision: drift's schema
  // SNAPSHOT generator (`drift_dev schema generate`, used by
  // `test/generated_migrations/schema_v11.dart` for the SchemaVerifier this
  // migration test depends on) names its historical table's Dart field after
  // the raw SQL column name, not the getter, so a column literally named
  // `text` still produces `late final GeneratedColumn<String> text = ...`
  // inside a class that `extends Table` — the identical
  // conflicting_field_and_method error, one file removed. No column actually
  // named `text` survives this repo's migration-test tooling, so both the
  // getter AND the underlying SQL column are `message_text` here.
  TextColumn get messageText => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// What this turn attached (v16), as `[{"mediaId":"<32hex>","kind":"image"}]`
  /// — see `encodeAttachments` in `media_analysis.dart`. Null when nothing was.
  TextColumn get attachmentsJson => text().nullable()();
  /// False for a turn the model must never see (v16): the declined-video pair
  /// is stored so the chat shows it, but a replay or resume skips it.
  BoolColumn get includeInModel =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The theme a user gets before they choose one.
///
/// Referenced by BOTH the `themeMode` column default and every place that
/// seeds the settings row, and that duplication is the point: a `CREATE TABLE`
/// default is frozen into a database when it is created, so a phone that
/// installed at schema v12 still carries `DEFAULT 'system'` forever. Seeding
/// from this constant instead of leaning on the column default is what makes
/// the answer the same on a three-year-old install and a fresh one.
const String kDefaultThemeMode = 'light';

/// What `CREATE TABLE` has frozen into this column since v1. See [AppSettings]
/// `themeMode`: this is a schema-compatibility constant, NOT a theme choice.
const String kFrozenThemeModeDefault = 'system';

/// Single-row app settings (always id = 0). Kept in the DB (not SharedPreferences)
/// so that, once encryption is enabled, even preferences stay inside the
/// encrypted store.
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  IntColumn get mode =>
      intEnum<TrackingMode>().withDefault(Constant(TrackingMode.track.index))();
  IntColumn get defaultCycleLength => integer().withDefault(const Constant(28))();
  IntColumn get defaultPeriodLength => integer().withDefault(const Constant(5))();
  // Defaults to LIGHT (see [kDefaultThemeMode]), not 'system'. The app is a
  // light-theme app unless the user says otherwise; following the OS was never
  // a deliberate product choice here, just the value the column happened to be
  // created with. This moves FRESH INSTALLS only -- an existing row already
  // holds a value, so no stored preference (including a deliberate 'system')
  // is touched and no migration is owed. `SettingsProvider.themeMode` carries
  // the matching pre-load fallback, which has to move with this one or the
  // default is only half true.
  /// The column default is the HISTORICAL value and must never change again.
  ///
  /// It is not the app's default theme -- [kDefaultThemeMode] is, and every
  /// site that seeds this row passes it explicitly, so this clause is never
  /// what decides a user's theme. It exists only to match what old databases
  /// physically contain: SQLite bakes a column default into the table at
  /// CREATE time and offers no way to alter it, so a database made at v12
  /// carries `DEFAULT 'system'` forever. Moving the declared default made
  /// `SchemaVerifier` report a divergence on every upgraded database, which
  /// broke `migrateAndValidate` for every migration test the moment the schema
  /// version was next bumped.
  TextColumn get themeMode =>
      text().withDefault(const Constant(kFrozenThemeModeDefault))();
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
  // Which consent disclosure the stored [analysisConsentUid] agreed to.
  //
  // A uid alone made consent one bit: "this user agreed". What they agreed to
  // was a sheet that says LunarFlow sends A PHOTO. Sending the tracked health
  // record is a materially different disclosure, so a stored version below
  // `kCurrentConsentVersion` reads as NOT consented and the sheet is shown
  // again. Widening an existing consent without re-asking is, in substance, no
  // consent at all.
  IntColumn get analysisConsentVersion => integer().nullable()();
  // Date of birth, collected in onboarding and editable in Settings. A full
  // date, not a year and not an age: an age is stale the day after it is
  // entered, and a year is a birthday-accurate age only half the time.
  // NULL means never answered — the whole profile is skippable.
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  // Height in canonical CENTIMETRES. The ft/in display choice is applied only
  // at the display boundary, exactly as `weightUnit` is, so switching units
  // never rewrites the stored value.
  //
  // Named `heightCm`, not `height`: `MediaItems.height` in this same file is a
  // pixel count, and two columns called `height` measuring different things is
  // the kind of ambiguity a doctor-facing readout cannot afford.
  RealColumn get heightCm => real().nullable()();
  // The user's current weight in canonical KILOGRAMS, for the doctor PDF header
  // and the BMI readout.
  //
  // Deliberately SEPARATE from the per-day `weight` metric in the day-tags blob
  // (`kMetricWeight`), which keeps driving the 90-day trend chart untouched.
  // They answer different questions — "what do you weigh" versus "what did you
  // weigh on 3 March" — and neither may read from the other.
  RealColumn get profileWeightKg => real().nullable()();
  // Age in years at the first period (menarche). A whole number of years is
  // what people actually remember; a date would be false precision.
  IntColumn get menarcheAge => integer().nullable()();
  // The contraception method in use, as a `contra_` key from
  // `kContraceptionOptions`. A STRING, not an enum index: the list will grow,
  // and an index would renumber every stored answer the day somebody inserts a
  // method in the middle of it.
  //
  // NULL means never asked, which is NOT the same as `contra_none`. Only the
  // second one says the user is using nothing, and only the second one is safe
  // to print in a doctor report.
  //
  // This is the highest-consequence column in the table: the subset in
  // `kOvulationSuppressingContraception` suppresses the fertile window
  // (`PredictionService.predictFromLogs`), because showing one to somebody who
  // does not ovulate is the app asserting something false about their body.
  TextColumn get contraceptionMethod => text().nullable()();
  // When that method started. Cycle data from before it is not comparable with
  // cycle data after it, which is exactly what makes the date worth storing
  // rather than just the method.
  DateTimeColumn get contraceptionStartDate => dateTime().nullable()();
  // Diagnoses a clinician has ALREADY GIVEN the user, as a JSON array of `dx_`
  // keys (`kDiagnosisOptions`) — the same shape as `trackingCategories`, and
  // for the same reason: a set that grows must not become a set of columns.
  //
  // What the user has been told, never what the app concluded. Nothing in this
  // codebase infers, suggests or scores any of these.
  TextColumn get knownDiagnoses => text().nullable()();
  // Currently breastfeeding. A NULLABLE bool, so the three states stay
  // distinct: null = never asked, false = answered no, true = answered yes.
  // A non-null default would silently answer "no" for every existing user.
  BoolColumn get breastfeeding => boolean().nullable()();
  // Breastfeeding since. Lactational amenorrhoea suppresses cycles outright, so
  // a gap in the log after this date is expected rather than a missed period.
  DateTimeColumn get breastfeedingSince => dateTime().nullable()();
  // The signup sexual-health baseline, as a JSON object (see
  // `SexualBaseline` in common/catalog.dart): typical frequency of sex and of
  // masturbation, general libido, and anything ever experienced.
  //
  // ONE column rather than four, and the reason is the same one behind
  // `trackingCategories` and `knownDiagnoses`: this question set will grow, and
  // a column per question means a migration per question.
  //
  // NULL means the wizard was skipped. It is never merged with the day-tags
  // blob — the baseline answers "how often, generally", the logs answer "what
  // happened on the 3rd", and a value that tries to be both ends up
  // disagreeing with itself.
  TextColumn get sexualHealthBaseline => text().nullable()();

  /// How much the user says her cycle varies, from `kCycleRegularityOptions`.
  ///
  /// Nullable, and null means NOBODY ASKED -- not "regular". The whole value of
  /// this column is in the first two or three months, before two complete
  /// cycles exist for `_stdDev` to work on, and treating silence as a claim of
  /// regularity would invent exactly the precision this is meant to stop.
  ///
  /// Only ever SUBTRACTS certainty downstream: it widens the +/- window
  /// (`cycleVariabilityPriorFor`) and the widest answer suppresses the fertile
  /// band (`cycleRegularityIsIrregular`), but no answer here raises confidence.
  TextColumn get cycleRegularity => text().nullable()();

  /// Pregnant now, or pregnant in the last three months: a key from
  /// `kPregnancyStatusOptions`. Null means NOBODY ASKED, not "no".
  TextColumn get pregnancyStatus => text().nullable()();

  /// For a birth or a loss, the date it happened (the wizard asks "how many
  /// weeks ago"). For the other answers, the date the answer was given -- a
  /// signup answer goes stale, and this is what lets a reader see how stale.
  DateTimeColumn get pregnancyStatusDate => dateTime().nullable()();

  /// Self-reported puberty stages (Tanner): keys from `kBreastStageOptions`
  /// (B, estrogen-driven) and `kPubicStageOptions` (P, adrenal androgens).
  /// Null means NOBODY ASKED.
  TextColumn get breastStage => text().nullable()();
  TextColumn get pubicHairStage => text().nullable()();

  /// How the user describes their puberty timing: a `kPubertyTiming*` key.
  TextColumn get pubertyTiming => text().nullable()();

  /// When the stages were last given. Stages describe the body AT that date,
  /// and the app's early / delayed reading needs the age then, not today.
  DateTimeColumn get pubertyAnsweredOn => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
