/// A day-editor section the user can show or hide from Settings › Customize
/// tracking. Hiding affects RENDERING ONLY — the day editor still decodes and
/// re-encodes every group, so a hidden category never loses logged data.
///
/// Deliberately NOT toggleable, and therefore absent from this list: Flow,
/// "Period ended today", Mood, Pain, BBT/OPK and Notes. Those are the app's
/// core cycle and fertility data — hiding them would break its primary
/// function (cycles are DERIVED from logged flow, so hiding it would silently
/// starve every prediction).
class TrackingCategory {
  const TrackingCategory(this.id, this.label, {this.defaultOn = true});

  final String id;
  final String label;

  /// New categories ship OFF so no existing user's day editor grows unasked.
  final bool defaultOn;
}

const String kCatPhysicalSymptoms = 'physical_symptoms';
const String kCatEmotional = 'emotional';
const String kCatSex = 'sex';
const String kCatDischarge = 'discharge';
const String kCatVaginal = 'vaginal';
const String kCatSexualHealth = 'sexual_health';
const String kCatLifestyle = 'lifestyle';
const String kCatWellbeing = 'wellbeing';
const String kCatMedications = 'medications';
const String kCatSleepQuality = 'sleep_quality';
const String kCatUrine = 'urine';
const String kCatDigestion = 'digestion';
const String kCatSkin = 'skin';

const List<TrackingCategory> kTrackingCategories = [
  TrackingCategory(kCatPhysicalSymptoms, 'Physical symptoms'),
  TrackingCategory(kCatEmotional, 'Emotional symptoms'),
  TrackingCategory(kCatSex, 'Sexual activity'),
  TrackingCategory(kCatDischarge, 'Discharge'),
  TrackingCategory(kCatVaginal, 'Vulva & vagina'),
  TrackingCategory(kCatSexualHealth, 'Sexual health'),
  TrackingCategory(kCatLifestyle, 'Lifestyle'),
  TrackingCategory(kCatWellbeing, 'Water, sleep, energy & stress'),
  TrackingCategory(kCatMedications, 'Medications'),
  TrackingCategory(kCatSleepQuality, 'Sleep quality', defaultOn: false),
  TrackingCategory(kCatUrine, 'Urine', defaultOn: false),
  TrackingCategory(kCatDigestion, 'Digestion', defaultOn: false),
  TrackingCategory(kCatSkin, 'Skin & hair', defaultOn: false),
];

/// The ids enabled for a user who has never opened Customize tracking.
Set<String> defaultEnabledCategoryIds() =>
    {for (final c in kTrackingCategories) if (c.defaultOn) c.id};
