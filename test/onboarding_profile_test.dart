import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// Onboarding is the ONLY place every user passes through — `AppGate` routes
/// account holders and local-only-hatch users alike into this wizard — so it is
/// where the four profile fields (date of birth, height, current weight, age at
/// first period) are collected.
///
/// Every one of them is REQUIRED as of 2026-09-14. They used to be skippable,
/// with a skip storing NULL; the wizard now refuses to advance past an
/// unanswered question, and the tests that pinned the old posture are inverted
/// below rather than deleted, so the reversal is a fact the suite states.
///
/// Modelled on `test/widget_test.dart`, which pumps the real [LunarFlowApp].

/// See `test/widget_test.dart`: the real [FirebaseAuthService] touches
/// `FirebaseAuth.instance`, which throws with no Firebase app initialized.
class _FakeSignedInAuthService implements AuthService {
  static const _user = AppUser(uid: 'test-uid', email: 'test@example.com');

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_user);
  @override
  AppUser? get currentUser => _user;
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
}

/// The default [SyncTrigger] persists the claim decision through
/// `flutter_secure_storage`, whose channel has no handler under
/// `flutter_tester`.
SyncTrigger _testSyncTrigger(AppDatabase db) => SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    );


Future<AppDatabase> _pumpOnboarding(WidgetTester tester) async {
  // Phone-sized, per the app_theme lesson in CLAUDE.md: an 800x600 default
  // surface hides layout faults that only appear at a real device width.
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    LunarFlowApp(
      database: db,
      authService: _FakeSignedInAuthService(),
      syncTrigger: _testSyncTrigger(db),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<AppSetting> _finishAndRead(WidgetTester tester, AppDatabase db) async {
  await finishWizard(tester);
  return db.getSettings();
}

void main() {
  testWidgets('the two profile pages appear, in order, after the cycle '
      'questions and before the mode question', (tester) async {
    await _pumpOnboarding(tester);

    // Each page is ANSWERED before Continue, which it did not used to need.
    // That is the point of the change and not incidental to this test: an
    // unanswered page no longer advances, so a bare tap would simply sit here.
    for (final question in const [
      'Welcome to LunarFlow',
      'Your data, on your terms',
      periodQuestion,
      cycleQuestion,
      dobQuestion,
      bodyQuestion,
      contraceptionQuestion,
      sexQuestion,
      shxQuestion,
      soloQuestion,
    ]) {
      expect(find.text(question), findsOneWidget, reason: 'expected $question');
      await answerVisiblePage(tester);
      await tapContinue(tester);
    }
    expect(find.text(modeQuestion), findsOneWidget);
    // Still the last page: the wizard grew, it did not sprout a second CTA.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('a date of birth picked in onboarding persists to the settings '
      'row', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, dobQuestion);

    // The picker opens on the year grid (nobody scrolls 30 years of months),
    // and its range IS the refusal — the youngest selectable year is the one
    // the range ends on, so tapping it is deterministic.
    final now = DateTime.now();
    final youngestYear = now.year - 8;
    await tester.tap(find.text('$youngestYear'));
    await tester.pumpAndSettle();

    final settings = await _finishAndRead(tester, db);
    expect(settings.dateOfBirth, DateTime(youngestYear, now.month, 1));
  });

  testWidgets('height, current weight and age at first period persist to the '
      'settings row in canonical units', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, bodyQuestion);

    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '165');
    await tester.enterText(
        find.byKey(const Key('onboarding-weight-field')), '61.5');
    await tester.pump();

    // The menarche stepper starts UNSET; the first tap seeds it, the second
    // increments — proving the control both answers and adjusts.
    final plus = find.descendant(
      of: find.byKey(const Key('menarche-stepper')),
      matching: find.byIcon(Icons.add),
    );
    await tester.tap(plus);
    await tester.pump();
    await tester.tap(plus);
    await tester.pumpAndSettle();

    final settings = await _finishAndRead(tester, db);
    expect(settings.heightCm, 165.0);
    expect(settings.profileWeightKg, 61.5);
    expect(settings.menarcheAge, isNotNull);
    expect(settings.menarcheAge, greaterThan(8));
    // The profile weight is its own field: it must NOT have been written as a
    // per-day weight metric (the 90-day trend chart's input).
    final logs = await db.select(db.dailyLogs).get();
    for (final l in logs) {
      expect(l.symptoms.contains('"weight"'), isFalse);
    }
  });

  testWidgets('every profile question is required, so all four columns are '
      'written', (tester) async {
    // The inverse of the test this replaces, which asserted that skipping left
    // all four NULL. There is no longer a skip: the birth-date page's decline
    // button is gone, and the wizard refuses to advance past any of them.
    final db = await _pumpOnboarding(tester);

    await walkTo(tester, dobQuestion);
    expect(find.text("I'd rather not say"), findsNothing,
        reason: 'the decline affordance was removed when this became required');

    final settings = await _finishAndRead(tester, db);
    expect(settings.onboardingComplete, isTrue);
    expect(settings.defaultCycleLength, 28);

    expect(settings.dateOfBirth, isNotNull);
    expect(settings.heightCm, isNotNull);
    expect(settings.profileWeightKg, isNotNull);
    expect(settings.menarcheAge, isNotNull);
  });

  testWidgets('an out-of-range height is REFUSED: the wizard does not advance '
      'and nothing is clamped', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, bodyQuestion);

    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '999');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(bodyQuestion), findsOneWidget);
    expect(find.text(modeQuestion), findsNothing);
    expect(find.textContaining('Enter a height between'), findsOneWidget);

    // Fixing it lets the wizard through, and the fixed value is what lands.
    // The rest of the page has to be supplied as well now — a blank field is
    // itself a refusal, so fixing only the bad value no longer advances.
    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '172.5');
    await tester.enterText(
        find.byKey(const Key('onboarding-weight-field')), '61.5');
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byKey(const Key('menarche-stepper')),
      matching: find.byIcon(Icons.add),
    ));
    await tester.pumpAndSettle();
    await tapContinue(tester);

    final settings = await _finishAndRead(tester, db);
    expect(settings.heightCm, 172.5,
        reason: 'the corrected value must be what lands, not a re-entered one');
  });

  testWidgets('SWIPING does not move the wizard at all — Continue is the only '
      'exit', (tester) async {
    // This used to swipe to the LAST page and assert that "Get started"
    // re-ran the refusal. Gesture scrolling is now off entirely, which is the
    // stronger guarantee: the bad page is never left in the first place. The
    // final re-check still exists in `_finish` as defence in depth.
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, bodyQuestion);

    await tester.enterText(
        find.byKey(const Key('onboarding-weight-field')), '900');
    await tester.pump();

    for (var i = 0; i < 10; i++) {
      // From a fixed point in the heading band, NOT the PageView's centre: the
      // centre sits on a text field on some pages, which claims a horizontal
      // drag for selection and swallows the swipe.
      await tester.dragFrom(const Offset(300, 150), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    expect(find.text(bodyQuestion), findsOneWidget,
        reason: 'a swipe carried the user off an unanswered page');
    expect(find.text(modeQuestion), findsNothing);

    final settings = await db.getSettings();
    expect(settings.onboardingComplete, isFalse);
    expect(settings.profileWeightKg, isNull);
  });

  group('contraception, the one clinical question the wizard asks', () {
    // Only this one, out of five Tier 1 fields. It earns a wizard page because
    // it changes what the app PREDICTS from day one — a method that suppresses
    // ovulation removes the fertile window — while diagnoses and breastfeeding
    // only colour how results are read, and can wait for Settings.
    testWidgets('walking past it is refused', (tester) async {
      // Inverted. This used to assert that skipping left the column null so
      // "never asked" stayed distinct from "uses nothing". The question is now
      // required, and `contra_none` carries the "uses nothing" meaning on its
      // own — so the distinction survives in the DATA even though the wizard
      // no longer offers a way to produce the null.
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, contraceptionQuestion);

      await tapContinue(tester);
      expect(find.text(contraceptionQuestion), findsOneWidget);
      expect((await db.getSettings()).onboardingComplete, isFalse);
    });

    testWidgets('a chosen method persists as its stable key', (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, contraceptionQuestion);

      await tester.dragUntilVisible(find.text('Hormonal IUD'),
          find.byType(Scrollable).last, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hormonal IUD'));
      await tester.pumpAndSettle();
      await tapContinue(tester);

      final settings = await _finishAndRead(tester, db);
      expect(settings.contraceptionMethod, 'contra_hormonal_iud');
    });

    testWidgets('"None" is answerable and is not the same as skipping',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, contraceptionQuestion);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tapContinue(tester);

      final settings = await _finishAndRead(tester, db);
      expect(settings.contraceptionMethod, 'contra_none');
    });
  });

  group('the sexual-health baseline, asked once at signup', () {
    // Each of these three pages asks TWO different questions: what is typically
    // true (stored as the baseline) and what is true today (seeded into today's
    // log). They are deliberately not the same field — the baseline answers
    // "how often, generally" and the log answers "what happened on the 13th",
    // and nothing merges them.
    testWidgets('the column is always written, because none of it is skippable',
        (tester) async {
      // Inverted. The null used to mean "never asked" and was reachable by
      // walking past all three pages. Every answer is now required, so the
      // column is always populated — the encoder's null branch survives for
      // rows written by older builds, not for anything this wizard can produce.
      final db = await _pumpOnboarding(tester);

      final settings = await _finishAndRead(tester, db);
      expect(settings.sexualHealthBaseline, isNotNull);
      final b = decodeSexualBaseline(settings.sexualHealthBaseline);
      expect(b.isEmpty, isFalse);
    });

    testWidgets('the typical-frequency answers persist as a baseline',
        (tester) async {
      final db = await _pumpOnboarding(tester);

      // Each page is finished BY HAND, not by [answerVisiblePage]: that helper
      // answers a refused page from scratch and would tap "Never", overwriting
      // the very frequency this test is asserting on.
      await walkTo(tester, sexQuestion);
      await tester.tap(find.text('Weekly').first);
      await tester.pumpAndSettle();
      await tapInGroup(tester, 'sex-today', 'None');
      await tapContinue(tester);

      await walkTo(tester, soloQuestion);
      await tester.tap(find.text('Rarely').first);
      await tester.pumpAndSettle();
      await tapInGroup(tester, 'solo-ways', 'Hands');
      await tapInGroup(tester, 'solo-time', 'Prefer not to answer');
      await tapInGroup(tester, 'solo-today', 'Not today');
      await tapContinue(tester);

      final settings = await _finishAndRead(tester, db);
      final b = decodeSexualBaseline(settings.sexualHealthBaseline);
      expect(b.sexFrequency, 'freq_weekly');
      expect(b.soloFrequency, 'freq_rarely');
    });

    testWidgets('history is a multi-select reusing the day-tag keys',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, shxQuestion);

      await tapInGroup(tester, 'shx-history', 'Bleeding after sex');
      await tapInGroup(tester, 'libido-baseline', 'Medium libido');
      await tapInGroup(tester, 'shx-today', 'None of these');
      await tapInGroup(tester, 'libido-today', 'High libido');
      await tapContinue(tester);

      final settings = await _finishAndRead(tester, db);
      expect(decodeSexualBaseline(settings.sexualHealthBaseline).history,
          contains('shx_post_coital'));
    });
  });

  group("seeding today's log from the wizard", () {
    testWidgets("a today answer is written as today's day tags",
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, soloQuestion);

      await tester.tap(find.text('Never').first);
      await tester.pumpAndSettle();
      await tapInGroup(tester, 'solo-ways', 'Hands');
      await tapInGroup(tester, 'solo-time', 'Prefer not to answer');
      await tapInGroup(tester, 'solo-today', 'Masturbation');
      await tapContinue(tester);

      await walkTo(tester, modeQuestion);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final today = dateOnly(DateTime.now());
      final logs = await db.select(db.dailyLogs).get();
      final todayLog =
          logs.where((l) => dateOnly(l.date) == today).firstOrNull;
      expect(todayLog, isNotNull);
      expect(decodeGroup(todayLog!.symptoms, kIntimacyKeyPrefix),
          {'slf_masturbation'});
    });

    testWidgets('the escape answers ARE logged, so signup day is never an '
        'empty row', (tester) async {
      // Inverted, and worth reading carefully. The old test asserted that a
      // user who answered nothing for today got NO row, because an empty row
      // reads as a logged day forever.
      //
      // Answering nothing is no longer possible: the three "today" questions
      // are required. What a user with nothing to report now produces is a row
      // of explicit NONE markers — `sex_none` (which already existed and is
      // logged by real users), plus the new `shx_none` and `slf_none`. That is
      // a positive statement ("nothing happened today"), not an empty row, so
      // the original hazard does not apply.
      //
      // The guard in `_finish` that refuses to write an empty day is kept: it
      // is simply unreachable through the wizard now, and still protects the
      // code path.
      final db = await _pumpOnboarding(tester);
      await finishWizard(tester);

      final logs = await db.select(db.dailyLogs).get();
      expect(logs, hasLength(1));
      expect(decodeGroup(logs.single.symptoms, kIntimacyKeyPrefix),
          {kSoloNone});
    });

    testWidgets('when the last period IS today, the flow and the tags land in '
        'ONE row', (tester) async {
      // The trap this exists for: `saveDay` REPLACES a day. Two separate
      // writes for the same date means the second erases the first, and the
      // period the user just entered disappears behind a day tag.
      final db = await _pumpOnboarding(tester);

      await walkTo(tester, 'When did your last period start?');
      final today = dateOnly(DateTime.now());
      await tester.tap(find.text('${today.day}').first);
      await tester.pumpAndSettle();

      await walkTo(tester, soloQuestion);
      await tester.tap(find.text('Never').first);
      await tester.pumpAndSettle();
      await tapInGroup(tester, 'solo-ways', 'Hands');
      await tapInGroup(tester, 'solo-time', 'Prefer not to answer');
      await tapInGroup(tester, 'solo-today', 'Masturbation');
      await tapContinue(tester);

      await walkTo(tester, modeQuestion);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final logs = await db.select(db.dailyLogs).get();
      final todayRows = logs.where((l) => dateOnly(l.date) == today).toList();
      expect(todayRows, hasLength(1));
      expect(todayRows.single.flow, isNotNull,
          reason: 'the period the user entered must survive the tag write');
      expect(decodeGroup(todayRows.single.symptoms, kIntimacyKeyPrefix),
          {'slf_masturbation'});
    });
  });
}
