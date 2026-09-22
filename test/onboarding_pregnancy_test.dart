import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// "Have you been pregnant in the last 3 months?" -- asked because a photo
/// cannot tell postpartum bleeding from a period.
///
/// REQUIRED like every other signup question, with "Prefer not to say" as the
/// escape so nobody has to disclose a miscarriage or termination to get in.
/// A birth or a loss also asks how many weeks ago, and that is required too:
/// "postpartum" without a date is the one fact the reading hinges on, missing.
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

Future<AppDatabase> _pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(LunarFlowApp(
    database: db,
    authService: _FakeSignedInAuthService(),
    syncTrigger: SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    ),
  ));
  await tester.pumpAndSettle();
  return db;
}

const _group = Key('pregnancy-status');
const _weeks = Key('pregnancy-weeks-stepper');

Future<void> _choose(WidgetTester tester, String label) async {
  final card = find.descendant(of: find.byKey(_group), matching: find.text(label));
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

/// The weeks stepper sits below five cards, and `ListView` builds lazily, so
/// it has no element until scrolled to.
Future<void> _revealWeeks(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(_weeks), 120,
      scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

/// Scrolls to the end of the page, so a `findsNothing` means "not built at
/// all" rather than "not built YET".
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
  await tester.pumpAndSettle();
}

Future<void> _addWeek(WidgetTester tester) async {
  final plus = find.descendant(
      of: find.byKey(_weeks), matching: find.byIcon(Icons.add));
  await tester.ensureVisible(plus);
  await tester.pumpAndSettle();
  await tester.tap(plus);
  await tester.pumpAndSettle();
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  testWidgets('every option is offered, including "Prefer not to say"',
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);

    for (final option in kPregnancyStatusOptions) {
      expect(
        find.descendant(of: find.byKey(_group), matching: find.text(option.label)),
        findsOneWidget,
        reason: 'missing "${option.label}"',
      );
    }
  });

  testWidgets('the page refuses to advance unanswered', (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);

    await tapContinue(tester);

    expect(find.text(pregnancyQuestion).hitTestable(), findsOneWidget);
    expect(find.textContaining('"Prefer not to say" is an answer'),
        findsOneWidget);
  });

  testWidgets('"No" is stored with the date it was given', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);
    await _choose(tester, 'No');
    await finishWizard(tester);

    final s = await db.getSettings();
    expect(s.pregnancyStatus, kPregnancyNone);
    expect(s.pregnancyStatusDate, _today());
  });

  testWidgets('"Prefer not to say" is stored, so it reads as declined, not '
      'as never asked', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);
    await _choose(tester, 'Prefer not to say');
    await finishWizard(tester);

    expect((await db.getSettings()).pregnancyStatus, kPregnancyPreferNot);
  });

  testWidgets('a birth asks how long ago, refuses without it, and stores the '
      'event date', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);

    await _scrollToEnd(tester);
    expect(find.byKey(_weeks), findsNothing,
        reason: 'the weeks question belongs to a birth or a loss only');
    await _choose(tester, 'Yes, I gave birth');
    await _revealWeeks(tester);
    expect(find.byKey(_weeks), findsOneWidget);

    await tapContinue(tester);
    expect(find.text(pregnancyQuestion).hitTestable(), findsOneWidget,
        reason: 'a birth without a date is the fact the reading needs, missing');

    await _addWeek(tester); // seeds 1
    await _addWeek(tester); // 2
    await finishWizard(tester);

    final s = await db.getSettings();
    final t = _today();
    expect(s.pregnancyStatus, kPregnancyBirth);
    expect(s.pregnancyStatusDate, DateTime(t.year, t.month, t.day - 14));
  });

  testWidgets('switching away from a birth drops the weeks question',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, pregnancyQuestion);
    await _choose(tester, 'Yes, a miscarriage or ended pregnancy');
    await _revealWeeks(tester);
    await _addWeek(tester);
    await _choose(tester, "Yes, I'm pregnant now");

    await _scrollToEnd(tester);
    expect(find.byKey(_weeks), findsNothing);
    await finishWizard(tester);

    final s = await db.getSettings();
    expect(s.pregnancyStatus, kPregnancyNow);
    expect(s.pregnancyStatusDate, _today(),
        reason: 'the weeks answer belonged to the loss, not to this answer');
  });

  group('pregnant now turns on pregnancy mode', () {
    const card = 'Track my pregnancy';

    testWidgets('the goal page offers it, already chosen, and finishing starts '
        'pregnancy mode dated from the last period', (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, pregnancyQuestion);
      await _choose(tester, "Yes, I'm pregnant now");
      await finishWizard(tester);

      final s = await db.getSettings();
      expect(s.mode, TrackingMode.pregnancy);
      // The walk answers the last-period page with today.
      expect(s.pregnancyStartDate, _today(),
          reason: 'a pregnancy is dated from the last menstrual period');
    });

    testWidgets('the user can still choose cycle tracking instead',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, pregnancyQuestion);
      await _choose(tester, "Yes, I'm pregnant now");
      await walkTo(tester, modeQuestion);
      expect(find.text(card), findsOneWidget);

      await tester.tap(find.text('Track my cycle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final s = await db.getSettings();
      expect(s.mode, TrackingMode.track);
      expect(s.pregnancyStartDate, isNull);
      expect(s.pregnancyStatus, kPregnancyNow,
          reason: 'the answer stands even when the mode is declined');
    });

    testWidgets('any other answer offers no pregnancy card', (tester) async {
      await _pumpOnboarding(tester);
      await walkTo(tester, pregnancyQuestion);
      await _choose(tester, 'No');
      await walkTo(tester, modeQuestion);
      expect(find.text(card), findsNothing);
    });

    testWidgets('changing the answer away from pregnant drops the mode',
        (tester) async {
      final db = await _pumpOnboarding(tester);
      await walkTo(tester, pregnancyQuestion);
      await _choose(tester, "Yes, I'm pregnant now");
      await _choose(tester, 'No');
      await finishWizard(tester);

      final s = await db.getSettings();
      expect(s.mode, TrackingMode.track,
          reason: 'a mode chosen for an answer the user withdrew is stale');
      expect(s.pregnancyStartDate, isNull);
    });
  });
}
