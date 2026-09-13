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
const String kCatWeight = 'weight';
const String kCatIntimacy = 'intimacy';

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
  TrackingCategory(kCatWeight, 'Weight', defaultOn: false),
  // Solo sexual activity. The ONE category added after the original set that
  // ships ON, and the exception is deliberate.
  //
  // It shipped off first, by the ordinary rule above. That was wrong: `kCatSex`
  // and `kCatSexualHealth` are both on by default, so defaulting this one off
  // made partnered sex visible and solo sex hidden behind a settings switch
  // nobody would find. Both ride the same synced day-tags blob at the same
  // sensitivity and carry the same shoulder-surf handling, so the default was
  // not protecting anything — the only thing it encoded was which sexual
  // behaviour counts as ordinary enough to show, which is a judgement this app
  // has no business making. Corrected 2026-09-13.
  //
  // The "no existing editor grows unasked" rule still holds everywhere else. It
  // is about not surprising users who never asked for a section; it is not a
  // licence to hide one group of a pair.
  //
  // Libido deliberately does NOT live here. It was already visible inside
  // Sexual health as a boolean, and moving it would make an existing control
  // vanish for everyone who had used it.
  //
  // Named 'Intimacy', not after its single chip. Two reasons, both real: a
  // section whose heading repeats its only option makes `find.text` ambiguous
  // (it matched both and took the widget tests down), and a discreet heading is
  // the same shoulder-surf judgement that keeps this group text-only in
  // `option_art.dart`.
  TrackingCategory(kCatIntimacy, 'Intimacy'),
];

/// The ids enabled for a user who has never opened Customize tracking.
Set<String> defaultEnabledCategoryIds() =>
    {for (final c in kTrackingCategories) if (c.defaultOn) c.id};
