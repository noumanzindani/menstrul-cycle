/// Core domain enums for LunaTrack.
///
/// These are stored in the database by their integer index via drift's
/// `intEnum<T>()`. IMPORTANT: never reorder or remove existing values — the
/// index is the persisted value. Add new values only at the END.
library;

/// Menstrual flow intensity for a single day.
enum FlowIntensity {
  none,
  spotting,
  light,
  medium,
  heavy,
  flooding,
}

/// What the user is using the app for. v1 ships `track`; the others are
/// reserved so the schema/logic can grow into them without a migration.
enum TrackingMode {
  track,
  conceive,
  perimenopause,
  pregnancy,
}

/// Kinds of local reminders. Notification scheduling maps off this.
enum ReminderType {
  periodSoon,
  fertileWindow,
  pill,
  logNudge,
  custom,
}

/// The four cycle phases used for calendar coloring and Home context.
/// `unknown` is used before enough data exists to place the user.
enum CyclePhase {
  menstrual,
  follicular,
  ovulatory,
  luteal,
  unknown,
}
