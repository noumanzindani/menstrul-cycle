import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/settings_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:menstrul_track/theme/app_theme.dart';

import 'support/onboarding_walk.dart';

/// Cycle length is asked in TWO places — the wizard and Settings — and the
/// subject of this file is that they agree on what a cycle may be.
///
/// They did not. Both clamped to 21..35 while FIGO calls 24..38 normal, so a
/// woman with a perfectly ordinary 37-day cycle could not enter it and was
/// pushed to 35 — every prediction then running days early until enough real
/// cycles accumulated to override the fallback. A range is a poor place to
/// encode normality: it cannot explain itself, so the user just finds the
/// stepper will not move and enters something false.
///
/// The ranges now live in `catalog.dart` and are asserted through those
/// constants rather than literals, so widening one surface cannot silently
/// leave the other behind.
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

// ---------------------------------------------------------------- onboarding

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

/// Taps [icon] on the wizard's cycle stepper [times] times. Deliberately more
/// taps than the span needs: the point is where it STOPS, not where it lands.
Future<void> _bumpWizard(WidgetTester tester, IconData icon, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.descendant(
      of: find.byKey(const Key('cycle-length-stepper')),
      matching: find.byIcon(icon),
    ));
    await tester.pumpAndSettle();
  }
}

// ------------------------------------------------------------------ settings

Future<void> _pumpSettings(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settings = SettingsProvider(SettingsRepository(db));
  await settings.load();
  // No premium.load(): it opens an in_app_purchase channel with no handler
  // under flutter_tester (mirrors the other settings harnesses).
  final premium = PremiumProvider(SettingsRepository(db));

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<PremiumProvider>.value(value: premium),
      ChangeNotifierProvider(
        create: (_) => AuthProvider(_FakeSignedInAuthService()),
      ),
      ChangeNotifierProvider(create: (_) => _testSyncTrigger(db)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls the cycle-length row into existence and returns its tile.
///
/// The row sits well down a lazily-built list, so `ensureVisible` alone has no
/// element to work with -- `scrollUntilVisible` has to build it first (the same
/// order `tapInGroup` uses in `support/onboarding_walk.dart`).
Future<Finder> _revealCycleRow(WidgetTester tester) async {
  final label = find.text('Average cycle length');
  if (label.evaluate().isEmpty) {
    await tester.scrollUntilVisible(label, 120,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  return find.ancestor(of: label, matching: find.byType(ListTile));
}

void main() {
  // The widget tests below assert that both surfaces honour whatever the
  // catalog says. This one is the other half: that what the catalog says is
  // wide enough. Stated as coverage of the STANDARD rather than as the literal
  // 20..45, so widening further stays green and narrowing back inside the
  // normal range -- the original bug -- cannot.
  test('the accepted span covers the whole of FIGO normal cycle frequency', () {
    // FIGO AUB System 1 (Munro et al. 2018): normal is 24..38 days. A range
    // that stops short of either end refuses a cycle a clinician calls normal,
    // and a stepper that will not move is a user entering something false.
    expect(kCycleLengthMin, lessThanOrEqualTo(24));
    expect(kCycleLengthMax, greaterThanOrEqualTo(38));
    // FIGO calls a bleed over 8 days prolonged, so the ceiling must clear it.
    expect(kPeriodLengthMax, greaterThanOrEqualTo(8));
  });

  testWidgets('the wizard accepts a cycle as long as the catalog allows',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    await _bumpWizard(tester, Icons.add, kCycleLengthMax - 28 + 3);
    await finishWizard(tester);

    expect((await db.getSettings()).defaultCycleLength, kCycleLengthMax);
  });

  testWidgets('the wizard accepts a cycle as short as the catalog allows',
      (tester) async {
    final db = await _pumpOnboarding(tester);
    await walkTo(tester, cycleQuestion);

    await _bumpWizard(tester, Icons.remove, 28 - kCycleLengthMin + 3);
    await finishWizard(tester);

    expect((await db.getSettings()).defaultCycleLength, kCycleLengthMin);
  });

  testWidgets('a long cycle entered in the wizard is still adjustable in '
      'Settings — the two ranges cannot drift apart', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Comfortably past the old 35 ceiling, and below the new one so BOTH
    // buttons ought to be live. Under the old clamp "+" was permanently
    // disabled here: the value rendered fine and could only ever go DOWN.
    const stored = 40;
    await SettingsProvider(SettingsRepository(db)).setCycleLength(stored);
    await _pumpSettings(tester, db);

    final row = await _revealCycleRow(tester);
    expect(find.descendant(of: row, matching: find.text('$stored days')),
        findsOneWidget);

    await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    expect((await db.getSettings()).defaultCycleLength, stored + 1);
  });
}
