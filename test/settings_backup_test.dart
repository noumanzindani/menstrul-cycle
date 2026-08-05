import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/settings_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Reports an already-signed-in user, like the other test files' fakes (see
/// `test/widget_test.dart` / `test/auth_gate_test.dart`) — this screen now
/// hosts `AccountSection` (task 11), which reads `AuthProvider`.
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

/// The Settings "Backup & restore" section: export opens a passphrase dialog
/// (with confirmation + validation), and restore CONFIRMS before touching data.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late PremiumProvider premium;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    // Note: no premium.load() — that opens an in_app_purchase platform channel
    // that isn't available under flutter_test (mirrors the Home test harnesses).
    premium = PremiumProvider(SettingsRepository(db));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>.value(value: premium),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(_FakeSignedInAuthService()),
        ),
        // Overridden decline/deviceId hooks so AccountSection's
        // declinedUidOnRecord() read doesn't touch the real
        // flutter_secure_storage plugin, which hangs under flutter_tester on
        // this host (see sync_trigger_test.dart / account_section_test.dart).
        ChangeNotifierProvider(
          create: (_) => SyncTrigger(
            db,
            readClaim: () async => null,
            writeClaim: (_) async {},
          ),
        ),
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

  testWidgets('shows the Backup & restore section', (tester) async {
    await pump(tester);
    // Scroll to the LAST of the three, not the first: dragUntilVisible stops on
    // the frame its target appears, so aiming at 'Back up my data' left the tile
    // below it unbuilt in the lazy list — and any tile added higher up in
    // Settings would silently break the assertion.
    await tester.dragUntilVisible(find.text('Restore from a backup'),
        find.byType(Scrollable).first, const Offset(0, -300));
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Back up my data'), findsOneWidget);
    expect(find.text('Restore from a backup'), findsOneWidget);
  });

  testWidgets('export opens a passphrase dialog and rejects a mismatch',
      (tester) async {
    await pump(tester);
    // Scroll past 'Restore from a backup' (the LAST of the three), not just
    // to 'Back up my data' itself -- see the identical note above: stopping
    // right at the target can leave it only partially visible (right at the
    // viewport edge), and any tile added higher up in Settings shifts this
    // further, as AccountSection (task 11) now does.
    await tester.dragUntilVisible(find.text('Restore from a backup'),
        find.byType(Scrollable).first, const Offset(0, -300));
    await tester.tap(find.text('Back up my data'));
    await tester.pumpAndSettle();

    expect(find.text('Set a passphrase'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2)); // passphrase + confirm

    await tester.enterText(fields.at(0), 'abcdef');
    await tester.enterText(fields.at(1), 'different');
    await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
    await tester.pumpAndSettle();

    expect(find.textContaining("don't match"), findsOneWidget);
  });

  testWidgets('restore confirms before doing anything destructive',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Restore from a backup'),
        find.byType(Scrollable).first, const Offset(0, -300));
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();

    // A destructive-action confirmation must appear FIRST (before any file pick).
    expect(find.text('Replace all current data?'), findsOneWidget);
    // Backing out changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace all current data?'), findsNothing);
  });

  // A .lunabak written before schema v3 has no trackingCategories key at all.
  // Restore must not throw on the missing key, and the absent value must land
  // as NULL so the user falls back to the registry defaults rather than to an
  // empty set (which would read as "everything turned off").
  test('settings JSON without trackingCategories restores as null', () {
    final row = AppSetting.fromJson(const {
      'id': 0,
      'mode': 0,
      'defaultCycleLength': 28,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'appLockEnabled': false,
      'premium': false,
      'onboardingComplete': true,
    });
    expect(row.trackingCategories, isNull);
  });
}
