import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// The bottom bar's arrival motion.
///
/// The structural half matters as much as the timing half: the five tabs live
/// in an `IndexedStack` so each keeps its scroll offset and form state, and the
/// transition wraps that stack rather than cross-fading two children. Swapping
/// in an `AnimatedSwitcher` would look almost identical and would silently
/// throw away every tab's state, so [_tabsStayMounted] guards the shape.
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

Future<void> _pumpToShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    LunarFlowApp(
      database: db,
      authService: _FakeSignedInAuthService(),
      syncTrigger: SyncTrigger(
        db,
        readClaim: () async => null,
        writeClaim: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await finishWizard(tester);
  await tester.pumpAndSettle();
}

/// The body's own fade, scoped by the [IndexedStack] it wraps -- `NavigationBar`
/// runs FadeTransitions of its own for the indicator.
double _bodyOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find
        .ancestor(
          of: find.byType(IndexedStack),
          matching: find.byType(FadeTransition),
        )
        .first)
    .opacity
    .value;

/// Scoped to the bar: 'Today' is also Home's own heading, and 'Calendar' etc.
/// appear in screen content too, so a bare `find.text` is ambiguous.
Future<void> _tapTab(WidgetTester tester, String label) => tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );

void main() {
  testWidgets('the arriving tab fades in rather than appearing outright',
      (tester) async {
    await _pumpToShell(tester);
    expect(_bodyOpacity(tester), 1.0);

    await _tapTab(tester, 'Calendar');
    await tester.pump();
    expect(_bodyOpacity(tester), 0.0);

    await tester.pump(const Duration(milliseconds: 100));
    final mid = _bodyOpacity(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(_bodyOpacity(tester), 1.0);
  });

  testWidgets('re-tapping the current tab is not an arrival and does not replay',
      (tester) async {
    await _pumpToShell(tester);

    // NavigationBar reports every tap, not only the ones that change the index.
    await _tapTab(tester, 'Today');
    await tester.pump();
    expect(_bodyOpacity(tester), 1.0);
  });

  testWidgets('reduced motion lands on the new tab in one frame',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpToShell(tester);
    await _tapTab(tester, 'Calendar');
    await tester.pump();
    expect(_bodyOpacity(tester), 1.0);
  });

  testWidgets('all five tabs stay mounted, so switching preserves their state',
      (tester) async {
    await _pumpToShell(tester);

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children, hasLength(5));

    // An AnimatedSwitcher ABOVE the stack would keep only the visible child
    // alive. Scoped to ancestors: the screens themselves use AnimatedSwitchers
    // of their own, and those are none of this test's business.
    expect(
      find.ancestor(
        of: find.byType(IndexedStack),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );

    // ...and the transition really does wrap the stack.
    expect(
      find.ancestor(
        of: find.byType(IndexedStack),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
  });
}
