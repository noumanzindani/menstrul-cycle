import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// Onboarding is the ONLY place every user passes through — `AppGate` routes
/// account holders and local-only-hatch users alike into this wizard — so it is
/// where the four profile fields (date of birth, height, current weight, age at
/// first period) are collected.
///
/// Every one of them is skippable, in the same sense the last-period date
/// already is: skipping is a first-class answer that leaves the column NULL,
/// and the app must behave exactly as it did before.
///
/// Modelled on `test/widget_test.dart`, which pumps the real [LunaTrackApp].

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

const _dobQuestion = 'When were you born?';
const _bodyQuestion = 'A few more details about you';
const _modeQuestion = 'What are you using LunaTrack for?';
const _contraceptionQuestion = 'Are you using contraception?';
const _sexQuestion = 'How often do you have sex?';
const _shxQuestion = 'Have you ever experienced any of these?';
const _soloQuestion = 'How often do you masturbate?';

Future<AppDatabase> _pumpOnboarding(WidgetTester tester) async {
  // Phone-sized, per the app_theme lesson in CLAUDE.md: an 800x600 default
  // surface hides layout faults that only appear at a real device width.
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    LunaTrackApp(
      database: db,
      authService: _FakeSignedInAuthService(),
      syncTrigger: _testSyncTrigger(db),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// Taps Continue until [question] is on screen. Deliberately not a hard-coded
/// tap count: where the profile pages sit is a layout decision, what these
/// tests are about is that they are reachable and that what is typed on them
/// lands in the settings row.
Future<void> _walkTo(WidgetTester tester, String question) async {
  // Bound, not a page count: the wizard grows, and a bound equal to the page
  // count silently stops working the day a page is added.
  for (var i = 0; i < 25 && find.text(question).evaluate().isEmpty; i++) {
    await _continue(tester);
  }
  expect(find.text(question), findsOneWidget);
}

Future<AppSetting> _finishAndRead(WidgetTester tester, AppDatabase db) async {
  await _walkTo(tester, _modeQuestion);
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  return db.getSettings();
}

void main() {
  testWidgets('the two profile pages appear, in order, after the cycle '
      'questions and before the mode question', (tester) async {
    await _pumpOnboarding(tester);

    expect(find.text('Welcome to LunaTrack'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Your data, on your terms'), findsOneWidget);
    await _continue(tester);
    expect(find.text('When did your last period start?'), findsOneWidget);
    await _continue(tester);
    expect(find.text('How long is your cycle, usually?'), findsOneWidget);

    await _continue(tester);
    expect(find.text(_dobQuestion), findsOneWidget);
    await _continue(tester);
    expect(find.text(_bodyQuestion), findsOneWidget);

    await _continue(tester);
    expect(find.text(_contraceptionQuestion), findsOneWidget);

    await _continue(tester);
    expect(find.text(_sexQuestion), findsOneWidget);
    await _continue(tester);
    expect(find.text(_shxQuestion), findsOneWidget);
    await _continue(tester);
    expect(find.text(_soloQuestion), findsOneWidget);

    await _continue(tester);
    expect(find.text(_modeQuestion), findsOneWidget);
    // Still the last page: the wizard grew, it did not sprout a second CTA.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('a date of birth picked in onboarding persists to the settings '
      'row', (tester) async {
    final db = await _pumpOnboarding(tester);
    await _walkTo(tester, _dobQuestion);

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
    await _walkTo(tester, _bodyQuestion);

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

  testWidgets('skipping every profile question leaves all four columns null',
      (tester) async {
    final db = await _pumpOnboarding(tester);

    await _walkTo(tester, _dobQuestion);
    // The explicit skip affordance, mirroring the last-period page's
    // "I'm not sure" — taking it must advance AND leave nothing behind.
    await tester.tap(find.text("I'd rather not say"));
    await tester.pumpAndSettle();
    expect(find.text(_bodyQuestion), findsOneWidget);

    final settings = await _finishAndRead(tester, db);
    // Not vacuous: onboarding really did run and write.
    expect(settings.onboardingComplete, isTrue);
    expect(settings.defaultCycleLength, 28);

    expect(settings.dateOfBirth, isNull);
    expect(settings.heightCm, isNull);
    expect(settings.profileWeightKg, isNull);
    expect(settings.menarcheAge, isNull);
  });

  testWidgets('an out-of-range height is REFUSED: the wizard does not advance '
      'and nothing is clamped', (tester) async {
    final db = await _pumpOnboarding(tester);
    await _walkTo(tester, _bodyQuestion);

    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '999');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(_bodyQuestion), findsOneWidget);
    expect(find.text(_modeQuestion), findsNothing);
    expect(find.textContaining('Enter a height between'), findsOneWidget);

    // Fixing it lets the wizard through, and the fixed value is what lands.
    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '172.5');
    await tester.pump();
    final settings = await _finishAndRead(tester, db);
    expect(settings.heightCm, 172.5);
  });

  testWidgets('SWIPING past an out-of-range height does not bypass the '
      'refusal — "Get started" sends the user back to the question',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await _walkTo(tester, _bodyQuestion);

    await tester.enterText(
        find.byKey(const Key('onboarding-weight-field')), '900');
    await tester.pump();

    // The Continue button is the checked exit; a horizontal swipe is not, so
    // the last page has to re-run the check before it writes anything.
    // Dragged from the question itself: the centre of the page sits on a text
    // field, which claims a horizontal drag for selection instead.
    // Swiped all the way to the LAST page, bounded rather than counted: a
    // single drag used to reach it, and silently stopped doing so when pages
    // were added between. What is being tested is that the final page re-runs
    // the refusal, not how many swipes away it is.
    for (var i = 0; i < 25 && find.text(_modeQuestion).evaluate().isEmpty; i++) {
      // From a fixed point in the heading band, NOT the PageView's centre:
      // the centre sits on a text field on some pages, which claims a
      // horizontal drag for selection and swallows the swipe.
      await tester.dragFrom(const Offset(300, 150), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text(_modeQuestion), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text(_bodyQuestion), findsOneWidget);
    expect(find.textContaining('Enter a weight between'), findsOneWidget);
    // Nothing was written: onboarding is still in front of the user.
    final settings = await db.getSettings();
    expect(settings.onboardingComplete, isFalse);
    expect(settings.profileWeightKg, isNull);
  });

  group('contraception, the one clinical question the wizard asks', () {
    // Only this one, out of five Tier 1 fields. It earns a wizard page because
    // it changes what the app PREDICTS from day one — a method that suppresses
    // ovulation removes the fertile window — while diagnoses and breastfeeding
    // only colour how results are read, and can wait for Settings.
    testWidgets('skipping it leaves the column null, as before', (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _contraceptionQuestion);

      final settings = await _finishAndRead(tester, db);
      expect(settings.contraceptionMethod, isNull,
          reason: 'never asked must not become an answer');
    });

    testWidgets('a chosen method persists as its stable key', (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _contraceptionQuestion);

      await tester.dragUntilVisible(find.text('Hormonal IUD'),
          find.byType(Scrollable).last, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hormonal IUD'));
      await tester.pumpAndSettle();

      final settings = await _finishAndRead(tester, db);
      expect(settings.contraceptionMethod, 'contra_hormonal_iud');
    });

    testWidgets('"None" is answerable and is not the same as skipping',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _contraceptionQuestion);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

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
    testWidgets('walking past all three leaves the column null', (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _soloQuestion);

      final settings = await _finishAndRead(tester, db);
      expect(settings.sexualHealthBaseline, isNull,
          reason: 'skipped must stay distinguishable from answered-nothing');
    });

    testWidgets('the typical-frequency answers persist as a baseline',
        (tester) async {
      final db = await _pumpOnboarding(tester);

      await _walkTo(tester, _sexQuestion);
      await tester.tap(find.text('Weekly').first);
      await tester.pumpAndSettle();

      await _walkTo(tester, _soloQuestion);
      await tester.tap(find.text('Rarely').first);
      await tester.pumpAndSettle();

      final settings = await _finishAndRead(tester, db);
      final b = decodeSexualBaseline(settings.sexualHealthBaseline);
      expect(b.sexFrequency, 'freq_weekly');
      expect(b.soloFrequency, 'freq_rarely');
    });

    testWidgets('history is a multi-select reusing the day-tag keys',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _shxQuestion);

      await tester.tap(find.text('Bleeding after sex').first);
      await tester.pumpAndSettle();

      final settings = await _finishAndRead(tester, db);
      expect(decodeSexualBaseline(settings.sexualHealthBaseline).history,
          contains('shx_post_coital'));
    });
  });

  group("seeding today's log from the wizard", () {
    testWidgets("a today answer is written as today's day tags",
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _soloQuestion);

      await tester.tap(find.text('Masturbation').first);
      await tester.pumpAndSettle();
      await _walkTo(tester, _modeQuestion);
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

    testWidgets('answering nothing for today writes NO log at all',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _modeQuestion);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(await db.select(db.dailyLogs).get(), isEmpty,
          reason: 'an empty day row would read as a logged day forever');
    });

    testWidgets('when the last period IS today, the flow and the tags land in '
        'ONE row', (tester) async {
      // The trap this exists for: `saveDay` REPLACES a day. Two separate
      // writes for the same date means the second erases the first, and the
      // period the user just entered disappears behind a day tag.
      final db = await _pumpOnboarding(tester);

      await _walkTo(tester, 'When did your last period start?');
      final today = dateOnly(DateTime.now());
      await tester.tap(find.text('${today.day}').first);
      await tester.pumpAndSettle();

      await _walkTo(tester, _soloQuestion);
      await tester.tap(find.text('Masturbation').first);
      await tester.pumpAndSettle();

      await _walkTo(tester, _modeQuestion);
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
