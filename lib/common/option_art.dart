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
/// Every `.svg` asset here MUST be monochrome and single-colour: `TrackArt`
/// repaints it with `BlendMode.srcIn`, which flattens the whole drawing to one
/// tint. A multi-colour file loses its colours; a light-mode-only palette
/// disappears in dark mode.
///
/// A non-`.svg` asset is rendered as full-colour raster with NO tint (see
/// `TrackArt._isRaster`). That is an owner decision per icon, not a default,
/// and it costs three things the tint gives away free: the mark no longer
/// follows the label colour, no longer adapts to the dark theme, and no longer
/// dims with the chip's disabled state. Prefer SVG unless the artwork itself is
/// the point.
const Map<String, String> kOptionArt = {
  // kSymptomOptions
  // Raster by owner decision: the illustration IS the mark. This group is now
  // COMPLETE -- every symptom option carries one, so none of it recolours with
  // the theme and none of it dims when a chip is disabled. See the raster
  // caveats above; that trade was made deliberately, group-wide.
  'cramps': 'assets/track/cramps.png',
  'headache': 'assets/track/headache.png',
  'bloating': 'assets/track/bloating.png',
  // Reversed 2026-09-14 by the owner, who supplied the art. This key sat in
  // [kNoArtKeys] because a mark for it had been drawn, shipped and withdrawn --
  // but that argument was made about a MONOCHROME GLYPH AT 16px, where every
  // abstract paired form tested read as a letterform ("oo", "8"). Both premises
  // moved: a raster mark renders at 28px (`TrackArt._rasterScale`) and is a
  // full-colour illustration of a clothed figure, so it is neither abstract nor
  // ambiguous. The shoulder-surf concern is unchanged and still real -- it is
  // now an accepted cost, not an unnoticed one.
  'tender_breasts': 'assets/track/tender_breasts.png',
  'acne': 'assets/track/acne.png',
  'fatigue': 'assets/track/fatigue.png',
  'nausea': 'assets/track/nausea.png',
  'backache': 'assets/track/backache.png',
  'cravings': 'assets/track/cravings.png',
  'insomnia': 'assets/track/insomnia.png',
  'diarrhea': 'assets/track/diarrhea.png',
  'constipation': 'assets/track/constipation.png',
  'dizziness': 'assets/track/dizziness.png',
  'discharge': 'assets/track/discharge.png',
  'migraine': 'assets/track/migraine.png',
  'hot_flashes': 'assets/track/hot_flashes.png',
  'night_sweats': 'assets/track/night_sweats.png',
  'pelvic_pain': 'assets/track/pelvic_pain.png',
  'leg_pain': 'assets/track/leg_pain.png',
  'swelling': 'assets/track/swelling.png',
  'fever': 'assets/track/fever.png',
  'chills': 'assets/track/chills.png',
  'clots_large': 'assets/track/clots_large.png',
  'soaking_hourly': 'assets/track/soaking_hourly.png',
  // kMoodOptions -- the one MIXED group. The last three are still glyphs, so
  // this row shows both kinds side by side: a glyph follows the label colour
  // and inverts in dark mode, an illustration does neither. Supplying art for
  // the remaining three is what makes the row consistent.
  'calm': 'assets/track/calm.png',
  'happy': 'assets/track/happy.png',
  'energetic': 'assets/track/energetic.png',
  'sensitive': 'assets/track/sensitive.png',
  // 'sad' is keyed sad but LABELLED "Low" -- the art matches the label.
  'sad': 'assets/track/sad.png',
  'anxious': 'assets/track/anxious.svg',
  'irritable': 'assets/track/irritable.svg',
  'angry': 'assets/track/angry.svg',
  // kEmotionalOptions -- complete.
  'mood_swings': 'assets/track/mood_swings.png',
  'anxiety': 'assets/track/anxiety.png',
  'low_mood': 'assets/track/low_mood.png',
  'irritability': 'assets/track/irritability.png',
  'sensitive_emotional': 'assets/track/sensitive_emotional.png',
  'tearful': 'assets/track/tearful.png',
  'low_motivation': 'assets/track/low_motivation.png',
  'brain_fog': 'assets/track/brain_fog.png',
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
///
/// As of 2026-09-14 every remaining entry is a SHOULDER-SURF decision, and that
/// uniformity is worth stating because it was not always true. Three keys were
/// excluded on other grounds and all three came back once art was supplied:
/// `tender_breasts` (the argument was about a 16px monochrome glyph, not a 28px
/// illustration) and the heavy-bleeding pair `clots_large` / `soaking_hourly`
/// (the argument was that "no pictogram can carry a number" — the art supplied
/// for `soaking_hourly` carries a literal "1h" badge, and `clots_large`'s label
/// states its threshold).
///
/// So the rule that survived contact is narrow: an exclusion holds when the
/// harm is someone ELSE reading the screen. An exclusion made because a mark
/// seemed undrawable is a prediction about illustration, and predictions like
/// that have lost three times. Weigh a new one accordingly.
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
  'shx_post_coital',
  // Solo sexual activity and libido level. The strongest case on this list:
  // `shx_` was already text-only for shoulder-surf reasons, and these are more
  // sensitive again. A libido level in particular is a three-state scale, and
  // any glanceable mark for it (a gauge, a flame, arrows) reads as a score of
  // the person rather than a note about a day.
  'slf_masturbation',
  'lbd_low',
  'lbd_medium',
  'lbd_high',
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
const Map<FlowIntensity, double> kFlowFill = {
  FlowIntensity.spotting: 0.15,
  FlowIntensity.light: 0.35,
  FlowIntensity.medium: 0.60,
  FlowIntensity.heavy: 0.85,
  FlowIntensity.flooding: 1.00,
};

/// The asset for [key], or null when it has none.
///
/// Null is a NORMAL answer, not an error: it covers the deliberate exclusions
/// in [kNoArtKeys] and any key this build has never heard of. The render sites
/// must degrade to a plain text chip, so a mixed group of decorated and
/// undecorated chips stays coherent — the sexual-activity, sexual-health,
/// intimacy and libido chips sit undecorated among decorated neighbours by
/// design, as does `soaking_hourly`.
String? artFor(String key) {
  // Prefix rule first: medication keys are user-created and unbounded, so they
  // can never appear in [kOptionArt] and must not fall through to null — a
  // Medications section of blank chips beside a decorated Symptoms section is
  // the thing that reads as broken.
  if (key.startsWith(kMedicationKeyPrefix)) return kMedicationArt;
  return kOptionArt[key];
}
