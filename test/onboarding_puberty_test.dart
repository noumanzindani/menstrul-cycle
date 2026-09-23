import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/puberty_stage.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// The two puberty pages: Tanner B stage (estrogen-driven) and P stage
/// (adrenal androgens), plus the self-reported timing and the app's own
/// reading. Required; the stages have no opt-out, the timing has "Not sure".
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

Future<void> _choose(WidgetTester tester, String group, String label) =>
    tapInGroup(tester, group, label);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  testWidgets('the B page offers exactly B1-B5, and says what it tracks',
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, breastQuestion);

    expect(find.textContaining('estrogen-driven puberty'), findsOneWidget);
    for (final o in kBreastStageOptions) {
      await tester.scrollUntilVisible(
          find.text(o.label), 120, scrollable: find.byType(Scrollable).last);
      expect(find.text(o.label), findsOneWidget, reason: 'missing ${o.label}');
    }
  });

  testWidgets('the P page says it tracks adrenal androgens', (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, pubicQuestion);
    expect(find.textContaining('adrenal androgens'), findsOneWidget);
    expect(find.text('P1 · Not started'), findsOneWidget);
  });

  testWidgets('each page refuses to advance unanswered', (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, breastQuestion);
    await tapContinue(tester);
    expect(find.text(breastQuestion).hitTestable(), findsOneWidget);

    await _choose(tester, 'breast-stage', 'B2 · Breast bud');
    await tapContinue(tester);
    expect(find.text(pubicQuestion).hitTestable(), findsOneWidget);

    // A stage alone is not enough: the timing question is required too.
    await _choose(tester, 'pubic-stage', 'P2 · First hair');
    await tapContinue(tester);
    expect(find.text(pubicQuestion).hitTestable(), findsOneWidget);
    expect(find.textContaining('"Not sure" is an answer'), findsOneWidget);
  });

  testWidgets('answers are stored with the date they were given',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, breastQuestion);
    await _choose(tester, 'breast-stage', 'B3 · Growing');
    await tapContinue(tester);
    await _choose(tester, 'pubic-stage', 'P2 · First hair');
    await _choose(tester, 'puberty-timing', 'Early');
    await finishWizard(tester);

    final s = await db.getSettings();
    expect(s.breastStage, 'tan_b3');
    expect(s.pubicHairStage, 'tan_p2');
    expect(s.pubertyTiming, kPubertyTimingEarly);
    expect(s.pubertyAnsweredOn, _today());
  });

  testWidgets("the app's own reading appears once stages are picked",
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, breastQuestion);
    await _choose(tester, 'breast-stage', 'B5 · Adult');
    await tapContinue(tester);
    await _choose(tester, 'pubic-stage', 'P1 · Not started');

    await tester.scrollUntilVisible(find.byKey(const Key('puberty-assessment')),
        120, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('B and P out of step'), findsOneWidget);
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
  });

  testWidgets('neither stage page offers "Prefer not to say"',
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, breastQuestion);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Prefer not to say'), findsNothing);

    await _choose(tester, 'breast-stage', 'B1 · Not started');
    await tapContinue(tester);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Prefer not to say'), findsNothing);
  });
}
