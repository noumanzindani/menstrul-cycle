import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/onboarding_walk.dart';

/// The regularity question, asked on the page that already asks the two
/// lengths.
///
/// It earns a place in the wizard on the same test the contraception page
/// passes and diagnoses fail: it changes what the app PREDICTS from day one.
/// `_stdDev` needs two complete cycles, so for the first two or three months
/// every user got the same ±1 day window regardless of whether her cycles were
/// steady or swinging three weeks.
///
/// OPTIONAL, like both steppers beside it. Null means nobody answered, which
/// `cycleVariabilityPriorFor` turns into no prior at all rather than into a
/// claim of regularity.
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

const _group = Key('cycle-regularity');

void main() {
  testWidgets('the answer the user taps is the one that is stored',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    final chip = find.descendant(
      of: find.byKey(_group),
      matching: find.text('It varies a lot'),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    await finishWizard(tester);
    expect((await db.getSettings()).cycleRegularity, kRegularityIrregular);
  });

  testWidgets('every option is offered, so no answer forces a false one',
      (tester) async {
    await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    for (final option in kCycleRegularityOptions) {
      expect(
        find.descendant(of: find.byKey(_group), matching: find.text(option.label)),
        findsOneWidget,
        reason: 'missing "${option.label}"',
      );
    }
  });

  testWidgets('the page still advances unanswered, and stores null', (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    // Not touched at all: the wizard must not have gained a required question.
    await finishWizard(tester);

    expect((await db.getSettings()).cycleRegularity, isNull,
        reason: 'silence is not a claim of regularity — a default here would '
            'invent the precision this question exists to remove');
  });
}
