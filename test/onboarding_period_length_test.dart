import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// Period length was the one prediction input the wizard never asked for.
///
/// `AppSettings.defaultPeriodLength` carries a column default of 5 and, before
/// this page grew a second stepper, NOTHING wrote it except the Settings
/// screen — which a first-run user never opens. So every user predicted with a
/// five-day bleed regardless of their own, and that number is not cosmetic: it
/// is `fallbackPeriodLength` in `PredictionService.predict`, which decides
/// `avgPeriod`, which decides whether `_phaseFor` calls today MENSTRUAL, which
/// is then stated as fact to Gemini in `buildHealthContext`.
///
/// Harness copied from `onboarding_profile_test.dart` rather than shared: this
/// repo keeps per-file test helpers, and only the multi-suite `walkTo` walk
/// lives in `support/`.
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

SyncTrigger _testSyncTrigger(AppDatabase db) => SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    );

Future<AppDatabase> _pumpOnboarding(WidgetTester tester) async {
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

const _cycleStepper = Key('cycle-length-stepper');
const _periodStepper = Key('period-length-stepper');

Future<void> _bump(WidgetTester tester, Key stepper, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.descendant(
      of: find.byKey(stepper),
      matching: find.byIcon(Icons.add),
    ));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('the cycle page asks for period length beside cycle length',
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    expect(find.byKey(_cycleStepper), findsOneWidget);
    expect(find.byKey(_periodStepper), findsOneWidget);
  });

  testWidgets('the period length the user picks is the one that is stored, '
      'and it does not disturb the cycle length', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    // 5 -> 7. Two taps rather than one so an off-by-one seed cannot pass.
    await _bump(tester, _periodStepper, 2);
    await finishWizard(tester);

    final settings = await db.getSettings();
    expect(settings.defaultPeriodLength, 7);
    // The two steppers share a page and a unit; crossing the callbacks would
    // be invisible on screen and wrong in every prediction afterwards.
    expect(settings.defaultCycleLength, 28);
  });

  testWidgets('the period stepper stops at 10, the same ceiling Settings uses',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    // 5 + 9 taps would reach 14 unbounded.
    await _bump(tester, _periodStepper, 9);
    await finishWizard(tester);

    expect((await db.getSettings()).defaultPeriodLength, 10);
  });
}
