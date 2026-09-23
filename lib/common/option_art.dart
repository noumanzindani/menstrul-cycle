import '../models/enums.dart';
import '../models/product_type.dart';
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
  // kMoodOptions -- complete.
  'calm': 'assets/track/calm.png',
  'happy': 'assets/track/happy.png',
  'energetic': 'assets/track/energetic.png',
  'sensitive': 'assets/track/sensitive.png',
  // 'sad' is keyed sad but LABELLED "Low" -- the art matches the label.
  'sad': 'assets/track/sad.png',
  'anxious': 'assets/track/anxious.png',
  'irritable': 'assets/track/irritable.png',
  'angry': 'assets/track/angry.png',
  // kEmotionalOptions -- complete.
  'mood_swings': 'assets/track/mood_swings.png',
  'anxiety': 'assets/track/anxiety.png',
  'low_mood': 'assets/track/low_mood.png',
  'irritability': 'assets/track/irritability.png',
  'sensitive_emotional': 'assets/track/sensitive_emotional.png',
  'tearful': 'assets/track/tearful.png',
  'low_motivation': 'assets/track/low_motivation.png',
  'brain_fog': 'assets/track/brain_fog.png',
  // kDischargeOptions -- complete.
  'cm_dry': 'assets/track/cm_dry.png',
  'cm_sticky': 'assets/track/cm_sticky.png',
  'cm_creamy': 'assets/track/cm_creamy.png',
  'cm_watery': 'assets/track/cm_watery.png',
  'cm_eggwhite': 'assets/track/cm_eggwhite.png',
  // kVaginalOptions -- complete.
  //
  // `vag_dryness` is ALSO a member of `kSexualHistoryOptions`, which re-uses
  // keys rather than defining its own. That list is rendered by
  // `onboarding_screen.dart`'s `_todayChips`, which builds a bare `Text` label
  // and never calls `artFor` -- so this illustration does not follow the key
  // into the "Have you ever experienced any of these?" question, where it would
  // sit beside two chips that are text-only for shoulder-surf reasons. Checked,
  // not assumed; if that helper ever grows art, re-check this one first.
  'vag_itching': 'assets/track/vag_itching.png',
  'vag_burning': 'assets/track/vag_burning.png',
  'vag_dryness': 'assets/track/vag_dryness.png',
  'vag_odor': 'assets/track/vag_odor.png',
  'vag_swelling': 'assets/track/vag_swelling.png',
  'vag_lumps': 'assets/track/vag_lumps.png',
  'vag_discomfort': 'assets/track/vag_discomfort.png',
  // kOpkOptions -- complete. The supplied `negative` art had the words
  // "Ovulation test" baked in beneath the disc; it was stripped, not shipped.
  // A caption inside a chip mark duplicates the label 6px to its right and
  // steals the space the mark needs to be legible at 28px.
  'negative': 'assets/track/negative.png',
  'positive': 'assets/track/positive.png',
  'peak': 'assets/track/peak.png',
  // kHabitOptions -- complete, and the only group whose marks are OBJECTS
  // rather than people (a cup, a glass, a cigarette). That is the artwork's
  // choice, not a rule; noted because it is visible beside the figure-based
  // groups above and reads as deliberate rather than inconsistent.
  'habit_exercise': 'assets/track/habit_exercise.png',
  'habit_caffeine': 'assets/track/habit_caffeine.png',
  'habit_alcohol': 'assets/track/habit_alcohol.png',
  'habit_smoking': 'assets/track/habit_smoking.png',
  'habit_meditation': 'assets/track/habit_meditation.png',
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
  // kSkinOptions -- complete.
  'skin_dry': 'assets/track/skin_dry.png',
  'skin_oily': 'assets/track/skin_oily.png',
  'skin_itchy': 'assets/track/skin_itchy.png',
  'skin_rash': 'assets/track/skin_rash.png',
  'skin_hair_loss': 'assets/track/skin_hair_loss.png',
  'skin_hair_oily': 'assets/track/skin_hair_oily.png',
  // kSexualHealthOptions and kLibidoOptions -- the ONLY members of those groups
  // with art. Owner decision 2026-09-14, taken against the recommendation
  // recorded on [kNoArtKeys]; the other five members stay text-only, so these
  // four sit decorated among undecorated neighbours rather than the reverse.
  'shx_condom': 'assets/track/shx_condom.png',
  'sex_none': 'assets/track/sex_none.png',
  'sex_protected': 'assets/track/sex_protected.png',
  'slf_masturbation': 'assets/track/slf_masturbation.png',
  'lbd_low': 'assets/track/lbd_low.png',
  'lbd_medium': 'assets/track/lbd_medium.png',
  'lbd_high': 'assets/track/lbd_high.png',
};

/// Options that must NEVER get artwork, each for a stated reason.
///
/// This set is the machine-checked half of a decision that would otherwise be a
/// memory. No test can fail because a drawing is undignified — but a test CAN
/// fail because a drawing exists where one was forbidden, and that is what
/// `kNoArtKeys` buys.
///
/// This set is now an EXPLICIT LIST, not a derived one, and that is the single
/// most important thing to know before editing it. It used to equal exactly the
/// four sensitive groups (`kSexOptions`, `kSexualHealthOptions`,
/// `kIntimacyOptions`, `kLibidoOptions`), which made it checkable against the
/// catalog. On 2026-09-14 the owner supplied art for `shx_condom` and all three
/// `lbd_` levels, so four of those eleven keys left. What remains cannot be
/// computed from group membership — `test/option_art_test.dart` therefore pins
/// it against a hand-written list instead.
///
/// Six keys, no longer one rule: four are the harm of someone ELSE reading the
/// screen, and two are absence markers with nothing to draw. A
/// pictogram is parsed in a glance where a word is not, and this app ships an
/// app-lock precisely because this data is sensitive.
///
/// The record of what has held and what has not, since a future reader will
/// otherwise have to re-derive it:
///
///   Reversed, and the argument was genuinely wrong. `tender_breasts` was
///   reasoned about a MONOCHROME GLYPH AT 16px; raster marks render at 28px in
///   full colour, so "every abstract paired form reads as a letterform" simply
///   stopped applying. `clots_large` / `soaking_hourly` were excluded because
///   "no pictogram can carry a number" — the art supplied for `soaking_hourly`
///   carries a literal "1h" badge.
///
///   Reversed, with the objection unanswered. `shx_condom` and the `lbd_`
///   levels are shoulder-surf cases, and nothing about the supplied art reduces
///   that: a condom pictogram is maximally glanceable, and the libido art is a
///   sad → neutral → happy ramp, which is the exact failure the old rationale
///   named ("reads as a score of the person rather than a note about a day").
///   This was raised before the change and overridden by the owner, which is
///   their call to make. It is recorded here so the next person does not
///   mistake it for an oversight and "fix" it in either direction.
const Set<String> kNoArtKeys = {
  // NOT one rule any more. `sex_unprotected` is here for a DIFFERENT reason
  // than the three below it, and collapsing the two would lose the only thing
  // that says which of them a new drawing could resolve.
  //
  // sex_unprotected — a LEGIBILITY hold, not a shoulder-surf one. Art was
  // supplied on 2026-09-14 and withheld: it is a red prohibition sign over two
  // hearts, which is what the supplied `sex_none` mark also is. Measured at
  // 20.5 mean per-pixel difference against it, where every other pair in that
  // batch scored 40–89; at the 28px these render, the two are the same picture.
  // They sit ADJACENT in one row ("None | Protected | Unprotected"), so the
  // failure is not subtle. Worse, crossed-out hearts reads as "no sex", which
  // is `sex_none`'s meaning — so the mark is arguably wrong and not merely
  // ambiguous. A DISTINCT mark closes this; nothing else about it is disputed.
  'sex_unprotected',
  // The remaining shoulder-surf exclusions. An icon is glanceable in a way a
  // word is not, which is the entire point of chip art and cuts both ways:
  // someone reading over the user's shoulder parses a pictogram far faster than
  // they parse "Emergency contraception". This app ships an app-lock precisely
  // because this data is sensitive. No art has been supplied for these three.
  'shx_emergency',
  'shx_pain',
  'shx_post_coital',
  // A THIRD reason, and neither of the two above it. These are absence
  // markers -- "none of these" and "not today" -- added on 2026-09-14 when the
  // sexual-health answers became required at signup and each set needed an
  // answer a user could give truthfully. There is no harm decision here and no
  // legibility dispute: there is simply nothing to draw. They sit here because
  // the partition admits no third state, NOT because art was forbidden, so
  // supplying a mark for either is a free choice rather than a reversal.
  kShxNone,
  kSoloNone,
};

/// The one icon shared by every user-created medication row.
const String kMedicationArt = 'assets/track/medication_generic.svg';

/// Marks for the numeric metric rows in the Wellbeing section.
///
/// Deliberately SEPARATE from [kOptionArt] rather than merged into it. These
/// keys are not [TrackOption] keys and these surfaces are not chips: a metric
/// row is a label plus −/+ steppers, so the mark sits ahead of the label
/// instead of inside a chip, and nothing here ever reaches [artFor]. Folding
/// them into [kOptionArt] would break the completeness test, which partitions
/// the CATALOG and would report every one of these as a ghost key.
///
/// [kMetricSleepQuality] is absent deliberately: no art was supplied for it,
/// and it renders in the SAME Wellbeing list as the other four, so reusing the
/// sleep mark would put two identical icons in one list. Absent yields null and
/// that row renders unmarked — visible, and the reason it is flagged rather
/// than papered over.
const Map<String, String> kMetricArt = {
  kMetricWater: 'assets/track/metric_water.png',
  kMetricSleep: 'assets/track/metric_sleep.png',
  kMetricEnergy: 'assets/track/metric_energy.png',
  kMetricStress: 'assets/track/metric_stress.png',
};

/// Marks for the menstrual products a change timer can run for.
///
/// COMPLETE as of 2026-09-14 — all four [ProductType] values. The render sites
/// still keep their Material fallback, and that is deliberate: [ProductType] is
/// an enum that can grow, and a new value would otherwise render a bare chip
/// beside four decorated ones. The fallback is now unreachable, which is the
/// point of leaving it.
///
/// Keyed by the enum rather than by name: [ProductType] is persisted BY NAME in
/// the session payload (see its doc), so a string key here would look like part
/// of that contract when it is only presentation.
const Map<ProductType, String> kProductArt = {
  ProductType.pad: 'assets/track/product_pad.png',
  ProductType.tampon: 'assets/track/product_tampon.png',
  ProductType.cupOrDisc: 'assets/track/product_cup.png',
  ProductType.periodUnderwear: 'assets/track/product_underwear.png',
};

/// Marks for the conditions in `kDiagnosisOptions`, keyed by the same stable
/// `dx_` keys that are persisted in `AppSettings.knownDiagnoses`.
///
/// A SEPARATE map rather than entries in [kOptionArt], for the same reason
/// [kMetricArt] and [kProductArt] are separate: `kDiagnosisOptions` is not one
/// of the day-editor chip groups that `option_art_test.dart` partitions, and
/// folding these in would silently redefine what that completeness test covers.
/// These render as `CheckboxListTile`s in a picker dialog, not as chips.
///
/// Four of the five are anatomical drawings of a uterus or an ovary. That is
/// the artwork's choice and it is the right one here — this dialog is reached
/// only from Settings, deliberately, by someone entering their own diagnoses,
/// which is not a shoulder-surf surface the way a day-editor chip row is.
const Map<String, String> kDiagnosisArt = {
  'dx_pcos': 'assets/track/dx_pcos.png',
  'dx_endometriosis': 'assets/track/dx_endometriosis.png',
  'dx_fibroids': 'assets/track/dx_fibroids.png',
  'dx_adenomyosis': 'assets/track/dx_adenomyosis.png',
  'dx_thyroid': 'assets/track/dx_thyroid.png',
};

/// The mark for the basal body temperature field — a [TextField], not a chip.
const String kBbtArt = 'assets/track/bbt.png';

/// Marks for seven Settings rows — date of birth, body measurements, clinical
/// state, cycle defaults. These are `ListTile.leading` slots, not chips, so they
/// are named constants rather than entries in a lookup map: each render site
/// names its own mark directly and nothing resolves one dynamically.
///
/// These seven are simply the rows art has been drawn for, and that is the
/// WHOLE rule. It is tempting to read a principle into which rows are
/// illustrated — facts about the user rather than actions, say — but the screen
/// refutes it: "Age at first period", "Contraception" and "Diagnoses" are as
/// much facts as the rows above them and still render a Material glyph. Settings
/// is therefore MIXED on purpose, and an un-illustrated row is a gap awaiting
/// art, never a statement that the row should stay plain.
///
/// The action rows (back up, restore, app lock, notifications, theme, delete
/// everything) are a separate question nobody has asked yet. An illustration
/// there would dress up a control whose glyph already says what it does, so do
/// not extend this set to them without checking first.
///
/// [kCycleLengthArt] and [kPeriodLengthArt] share a composition on purpose — a
/// ring of arrows around a centre — because they are consecutive rows stating
/// the same kind of number. The pixel difference between them (28.1 at the 28px
/// they render) therefore sits below the band every other shipped pair scores,
/// and that number is misleading here: the ring is common, but the centres are
/// a calendar and a blood drop, which is the part the eye reads. See the commit
/// that added them for the comparison at render size.
const String kDobArt = 'assets/track/set_dob.png';
const String kHeightArt = 'assets/track/set_height.png';
const String kWeightArt = 'assets/track/set_weight.png';
const String kBreastfeedingArt = 'assets/track/set_breastfeeding.png';
const String kPregnancyArt = 'assets/track/set_pregnancy.png';
const String kCycleLengthArt = 'assets/track/set_cycle_length.png';
const String kPeriodLengthArt = 'assets/track/set_period_length.png';
// Added 2026-09-14, and they are exactly the two rows the comment above called
// out as facts still rendering a Material glyph. That gap is now closed, which
// leaves "Age at first period" as the only fact row without a mark.
const String kContraceptionArt = 'assets/track/set_contraception.png';
const String kDiagnosesArt = 'assets/track/set_diagnoses.png';
// Age at first period was named in the comment above as the last fact row still
// on a Material glyph. It no longer is, so that list is now closed.
const String kMenarcheArt = 'assets/track/set_menarche.png';
// The contraception start date only. The breastfeeding since-date row uses the
// same `Icons.event_outlined` and is deliberately left on it: one supplied mark
// cannot mean both, and reusing this one would show a contraception drawing
// against a breastfeeding question.
const String kContraceptionSinceArt = 'assets/track/set_since.png';

/// Marks for the three prediction cards on the Today dashboard.
///
/// These sit BESIDE `_InfoCard`'s accent dot, never in place of it. The dot
/// carries the `PhaseColors` token that ties the card to the month ring and the
/// calendar, and only [kCardPeriodArt] happens to share its phase's hue (345
/// against menstrual's 346); the fertile-window mark is blue-violet where the
/// fertile token is teal, and the PMS mark's dominant colour is a figure's
/// hair. Swapping the dot out would have dropped the key on two of three.
const String kCardPeriodArt = 'assets/track/card_period.png';
const String kCardFertileArt = 'assets/track/card_fertile.png';
const String kCardPmsArt = 'assets/track/card_pms.png';

/// Marks for the Today phase card, keyed by the phase it is naming.
///
/// [CyclePhase.unknown] is deliberately ABSENT rather than mapped to a
/// placeholder. It is the state where the app does not yet know where the user
/// is, and a picture there would assert something the card's own copy declines
/// to. A null lookup renders the card exactly as it did before.
///
/// Like the prediction cards, these sit beside the phase dot rather than
/// replacing it — `_PhaseCard` tints its whole surface with the same
/// `PhaseColors` token, so the dot is the one place that colour is stated at
/// full strength.
///
/// [CyclePhase.menstrual]'s mark is the odd one out: it is a cut-out
/// composition where the other three sit on a lavender disc. Its source shipped
/// the transparency CHECKERBOARD as real pixels (an RGB file with no alpha at
/// all), which the saturation-based background cut removes — but there was
/// never a disc underneath. Only one phase shows at a time, so the difference
/// is visible across a month rather than side by side.
const Map<CyclePhase, String> kPhaseArt = {
  CyclePhase.menstrual: 'assets/track/phase_menstrual.png',
  CyclePhase.follicular: 'assets/track/phase_follicular.png',
  CyclePhase.ovulatory: 'assets/track/phase_ovulatory.png',
  CyclePhase.luteal: 'assets/track/phase_luteal.png',
};

/// The Account group's two rows, in `account_section.dart`.
const String kAccountArt = 'assets/track/set_account.png';
const String kSignOutArt = 'assets/track/set_signout.png';

/// The five bottom-navigation destinations, in shell order.
///
/// This surface fights the artwork harder than any other, and the trade was
/// made with the comparison in hand rather than by eye. Rendered at the real
/// 24px against the live bar, the illustrations lose contrast badly where the
/// Material glyphs are near-black, and the Forecast and Insights marks turn to
/// mush at that size. (Index 2 is now the Assistant; Forecast left the bar on
/// 2026-09-23.)
///
/// Worse, `NavigationDestination` carries an `icon`/`selectedIcon` pair that one
/// raster cannot express: the same file serves both states, so the selection
/// pill becomes the only cue — and the pill is pink behind a pink Today mark.
/// [kNavUnselectedOpacity] is the compensation: the unselected marks are dimmed
/// so the selected one reads as lit, restoring a per-state difference the pair
/// would otherwise have provided for free.
///
/// Shipped at the owner's explicit direction after seeing that comparison. If
/// it reads badly on a real device, the revert is this map and `app_shell.dart`
/// — nothing else consumes either.
const List<String> kNavArt = [
  'assets/track/nav_today.png',
  'assets/track/nav_calendar.png',
  // TODO(owner): supply assets/track/nav_assistant.png and point index 2 at
  // it (then list it in option_art_test's raster set). Until it exists the
  // Assistant tab borrows the old Forecast tab's mark, which is also why
  // that file is still bundled.
  'assets/track/nav_forecast.png',
  'assets/track/nav_insights.png',
  'assets/track/nav_settings.png',
];

/// How much an UNSELECTED navigation mark is dimmed. See [kNavArt].
const double kNavUnselectedOpacity = 0.55;

/// Every [kDobArt]-family mark, for the asset tests to enumerate.
///
/// Exists so that adding a Settings mark and forgetting to cover it cannot pass
/// — the tests walk this list rather than a hand-copied one.
const List<String> kSettingsArt = [
  kDobArt,
  kHeightArt,
  kWeightArt,
  kBreastfeedingArt,
  kPregnancyArt,
  kCycleLengthArt,
  kPeriodLengthArt,
  kContraceptionArt,
  kDiagnosesArt,
  kMenarcheArt,
  kContraceptionSinceArt,
  kAccountArt,
  kSignOutArt,
];

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
