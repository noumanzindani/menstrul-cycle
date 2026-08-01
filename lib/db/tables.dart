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

  @override
  Set<Column> get primaryKey => {id};
}
