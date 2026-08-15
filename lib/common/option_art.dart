import '../models/enums.dart';
import 'catalog.dart';

/// Per-option chip artwork, keyed by the STABLE [TrackOption.key].
///
/// Deliberately a standalone map rather than a field on [TrackOption]. Three
/// reasons, in order of weight:
///
/// 1. A map can be ENUMERATED; a field cannot. The completeness guarantee in
///    `test/option_art_test.dart` — every catalog key is classified exactly
///    once — is only writable against a collection. An optional field is the
///    option that looks safest because it breaks nothing, and that is precisely
///    the problem: it also enforces nothing.
/// 2. `catalog.dart` is a persistence contract (see its `TrackOption` doc: keys
///    are "STABLE identifiers persisted in the DB"). Presentation must not leak
///    into it, and both of its POSITIONAL runtime constructors
///    (`pdf_report_service.dart`, `day_entry_form.dart`'s medication chips)
///    keep compiling untouched.
/// 3. Medications need a PREFIX rule, not a per-instance value — their keys are
///    user-created and unbounded, so no field could ever be populated for them.
///
/// Every asset here MUST be a monochrome, single-colour SVG: `TrackArt`
/// repaints it with `BlendMode.srcIn`, which flattens the whole drawing to one
/// tint. A multi-colour file loses its colours; a light-mode-only palette
/// disappears in dark mode.
const Map<String, String> kOptionArt = {
  // kSymptomOptions
  'cramps': 'assets/track/cramps.svg',
  'headache': 'assets/track/headache.svg',
  'bloating': 'assets/track/bloating.svg',
  'acne': 'assets/track/acne.svg',
  'fatigue': 'assets/track/fatigue.svg',
  'nausea': 'assets/track/nausea.svg',
  'backache': 'assets/track/backache.svg',
  'cravings': 'assets/track/cravings.svg',
  'insomnia': 'assets/track/insomnia.svg',
  'diarrhea': 'assets/track/diarrhea.svg',
  'constipation': 'assets/track/constipation.svg',
  'dizziness': 'assets/track/dizziness.svg',
  'discharge': 'assets/track/discharge.svg',
  'migraine': 'assets/track/migraine.svg',
  'hot_flashes': 'assets/track/hot_flashes.svg',
  'night_sweats': 'assets/track/night_sweats.svg',
  'pelvic_pain': 'assets/track/pelvic_pain.svg',
  'leg_pain': 'assets/track/leg_pain.svg',
  'swelling': 'assets/track/swelling.svg',
  'fever': 'assets/track/fever.svg',
  'chills': 'assets/track/chills.svg',
  // kMoodOptions
  'calm': 'assets/track/calm.svg',
  'happy': 'assets/track/happy.svg',
  'energetic': 'assets/track/energetic.svg',
  'sensitive': 'assets/track/sensitive.svg',
  'sad': 'assets/track/sad.svg',
  'anxious': 'assets/track/anxious.svg',
  'irritable': 'assets/track/irritable.svg',
  'angry': 'assets/track/angry.svg',
  // kEmotionalOptions
  'mood_swings': 'assets/track/mood_swings.svg',
  'anxiety': 'assets/track/anxiety.svg',
  'low_mood': 'assets/track/low_mood.svg',
  'irritability': 'assets/track/irritability.svg',
  'sensitive_emotional': 'assets/track/sensitive_emotional.svg',
  'tearful': 'assets/track/tearful.svg',
  'low_motivation': 'assets/track/low_motivation.svg',
  'brain_fog': 'assets/track/brain_fog.svg',
  // kDischargeOptions
  'cm_dry': 'assets/track/cm_dry.svg',
  'cm_sticky': 'assets/track/cm_sticky.svg',
  'cm_creamy': 'assets/track/cm_creamy.svg',
  'cm_watery': 'assets/track/cm_watery.svg',
  'cm_eggwhite': 'assets/track/cm_eggwhite.svg',
  // kVaginalOptions
  'vag_itching': 'assets/track/vag_itching.svg',
  'vag_burning': 'assets/track/vag_burning.svg',
  'vag_dryness': 'assets/track/vag_dryness.svg',
  'vag_odor': 'assets/track/vag_odor.svg',
  'vag_swelling': 'assets/track/vag_swelling.svg',
  'vag_lumps': 'assets/track/vag_lumps.svg',
  'vag_discomfort': 'assets/track/vag_discomfort.svg',
  // kOpkOptions
  'negative': 'assets/track/negative.svg',
  'positive': 'assets/track/positive.svg',
  'peak': 'assets/track/peak.svg',
  // kHabitOptions
  'habit_exercise': 'assets/track/habit_exercise.svg',
  'habit_caffeine': 'assets/track/habit_caffeine.svg',
  'habit_alcohol': 'assets/track/habit_alcohol.svg',
  'habit_smoking': 'assets/track/habit_smoking.svg',
  'habit_meditation': 'assets/track/habit_meditation.svg',
  // kUrineOptions
  'urn_frequent': 'assets/track/urn_frequent.svg',
  'urn_urgency': 'assets/track/urn_urgency.svg',
  'urn_burning': 'assets/track/urn_burning.svg',
  'urn_dark': 'assets/track/urn_dark.svg',
  'urn_cloudy': 'assets/track/urn_cloudy.svg',
  'urn_blood': 'assets/track/urn_blood.svg',
  'urn_leaking': 'assets/track/urn_leaking.svg',
  // kDigestionOptions
  'dig_gas': 'assets/track/dig_gas.svg',
  'dig_heartburn': 'assets/track/dig_heartburn.svg',
  'dig_no_bm': 'assets/track/dig_no_bm.svg',
  'dig_loose_stool': 'assets/track/dig_loose_stool.svg',
  'dig_hard_stool': 'assets/track/dig_hard_stool.svg',
  // kSkinOptions
  'skin_dry': 'assets/track/skin_dry.svg',
  'skin_oily': 'assets/track/skin_oily.svg',
  'skin_itchy': 'assets/track/skin_itchy.svg',
  'skin_rash': 'assets/track/skin_rash.svg',
  'skin_hair_loss': 'assets/track/skin_hair_loss.svg',
  'skin_hair_oily': 'assets/track/skin_hair_oily.svg',
};

/// Options that must NEVER get artwork, each for a stated reason.
///
/// This set is the machine-checked half of a decision that would otherwise be a
/// memory. No test can fail because a drawing is undignified — but a test CAN
/// fail because a drawing exists where one was forbidden, and that is what
/// `kNoArtKeys` buys.
const Set<String> kNoArtKeys = {
  // Sexual activity. An icon is glanceable in a way a word is not — which is
  // the entire point of this feature, and it cuts both ways. Someone reading
  // over the user's shoulder parses a pictogram far faster than they parse
  // "Unprotected". This app ships an app-lock precisely because this data is
  // sensitive; adding a symbol that survives a half-second glance works against
  // that. Text-only is the deliberate choice, not an oversight.
  'sex_none',
  'sex_protected',
  'sex_unprotected',
  // Sexual health. Same shoulder-surf reasoning; "Emergency contraception" in
  // particular should not be legible from across a room.
  'shx_condom',
  'shx_emergency',
  'shx_pain',
  'shx_high_libido',
  // Tender breasts. Not a backlog item — this was DRAWN, shipped to a device,
  // and withdrawn. The constraint is that it must convey tenderness without
  // drawing anatomy (this chip is glanceable on a shared screen), and every
  // abstract paired form tested read as a letterform: thin rings read as "oo",
  // heavy rings with centre dots read as "∞". A mark that is misread is worse
  // than no mark, because it sits beside four that ARE legible and implies the
  // reader is failing to decode it. The plain text chip is the better answer.
  // Revisit only with a mark that is unambiguous at 16px — not by drawing this
  // one again.
  'tender_breasts',
};

/// The one icon shared by every user-created medication row.
const String kMedicationArt = 'assets/track/medication_generic.svg';

/// Flow-intensity artwork: a drop whose filled fraction rises with the level.
///
/// [FlowIntensity.none] is deliberately absent — it is the "Period ended today"
/// switch, not a chip, and an empty drop next to it would read as a sixth
/// intensity.
///
/// Tinted by the caller in ONE constant red (`PhaseColors.menstrual`), NOT the
/// graduated `FlowIntensityUi.color` ramp. The fill fraction already encodes
/// intensity; fading the colour too encodes it twice, and on device that
/// double-fade left Spotting and Light almost invisible in dark mode, because
/// the ramp reaches its lighter steps with alpha. The ramp is still correct on
/// the calendar and the month ring, which have no fill fraction and so need
/// colour as their only channel — which is why this was fixed at the chip
/// rather than in the shared ramp.
const Map<FlowIntensity, String> kFlowArt = {
  FlowIntensity.spotting: 'assets/track/flow_1_spotting.svg',
  FlowIntensity.light: 'assets/track/flow_2_light.svg',
  FlowIntensity.medium: 'assets/track/flow_3_medium.svg',
  FlowIntensity.heavy: 'assets/track/flow_4_heavy.svg',
  FlowIntensity.flooding: 'assets/track/flow_5_flooding.svg',
};

/// The asset for [key], or null when it has none.
///
/// Null is a NORMAL answer, not an error: it covers the deliberate exclusions
/// in [kNoArtKeys] and any key this build has never heard of. The render sites
/// must degrade to a plain text chip, so a mixed group of decorated and
/// undecorated chips stays coherent — the sexual-activity, sexual-health and
/// tender-breasts chips sit undecorated among decorated neighbours by design.
String? artFor(String key) {
  // Prefix rule first: medication keys are user-created and unbounded, so they
  // can never appear in [kOptionArt] and must not fall through to null — a
  // Medications section of blank chips beside a decorated Symptoms section is
  // the thing that reads as broken.
  if (key.startsWith(kMedicationKeyPrefix)) return kMedicationArt;
  return kOptionArt[key];
}
