import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// The onboarding wizard's reduced-motion contract.
///
/// The rule is the one [MonthRing] and [FlowDrop] already keep: reduced motion
/// jumps to the END state, never to the start. For a `PageView` that means
/// `jumpToPage`, not a 250ms `nextPage` — the destination question is simply
/// already there on the next frame.
///
/// Written because the wizard shipped WITHOUT this guard while both painters
/// had it, which made three 250ms animations the only unguarded motion in
/// `lib/`. A single-frame `pump()` is the whole point of these tests: it is
/// what distinguishes "landed" from "travelling", and `pumpAndSettle` cannot
/// tell the two apart.
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

Future<void> _pumpOnboarding(WidgetTester tester) async {
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
}

PageController _wizardController(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

/// Presses Continue on the welcome page WITHOUT settling, so the caller owns
/// the first frame after the page change.
///
/// Page 0 is the welcome copy, which asks nothing — deliberately the page used
/// here, so these tests exercise the transition and never a validation rule.
Future<void> _continueFromWelcome(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
}

void main() {
  testWidgets('reduced motion LANDS on the next question in one frame',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpOnboarding(tester);
    expect(_wizardController(tester).page, 0.0);

    await _continueFromWelcome(tester);
    await tester.pump();

    // Landed, not travelling. Any value strictly between 0 and 1 here would
    // mean the 250ms curve is still running.
    expect(_wizardController(tester).page, 1.0);
  });

  testWidgets('normal motion still TRAVELS, so the guard is load-bearing',
      (tester) async {
    await _pumpOnboarding(tester);

    await _continueFromWelcome(tester);
    await tester.pump();

    // The control. If this ever reads 1.0 the wizard stopped animating for
    // everyone and the test above proves nothing.
    expect(_wizardController(tester).page, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(_wizardController(tester).page, 1.0);
  });

  testWidgets('the step progress bar lands on its new value in one frame',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpOnboarding(tester);
    await _continueFromWelcome(tester);
    await tester.pump();

    final landed =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value;
    await tester.pumpAndSettle();
    final settled =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value;

    // Settling changes nothing, because there was nothing left to travel.
    expect(landed, settled);
  });
}
