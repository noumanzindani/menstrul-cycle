import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/settings_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/media_analysis.dart' show kCurrentConsentVersion;
import 'package:menstrul_track/theme/app_theme.dart';

/// Reports an already-signed-in user (copied from `settings_clinical_test.dart` /
/// `settings_backup_test.dart` — there is no shared fake across these files).
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

/// `SettingsScreen.handlePhotoDescriptionsToggle` — the Settings "Describe
/// photos" switch's `onChanged`, pulled out to a `@visibleForTesting` static
/// method for exactly the reason this file exists: the switch itself is
/// gated on `analysisAvailable`, a compile-time `String.fromEnvironment`
/// that is false under plain `flutter test` (see `media_analyzer.dart`), so
/// no widget test can tap the real `SwitchListTile` in `SettingsScreen`'s
/// tree. These tests wire a bare `TextButton` straight to the real handler
/// instead, inside the same `SettingsProvider` / `AuthProvider` context the
/// screen itself provides — real code, real consent sheet, just reached
/// without needing the compiled-in API key.
///
/// This is the regression suite for the CRITICAL final-review finding: the
/// toggle used to call `settings.setAnalysisConsent(uid)` directly on ON,
/// stamping `kCurrentConsentVersion` consent without ever showing the
/// version's disclosure. See `handlePhotoDescriptionsToggle`'s doc comment.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {bool enable = true}) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        // `lazy: false`: nothing in this minimal harness READS AuthProvider
        // during build (unlike the real SettingsScreen tree, where
        // AccountSection does), so a lazy provider would not even be
        // CONSTRUCTED — and so would not have subscribed to
        // `authStateChanges()` — until the button's `onPressed` reads it for
        // the first time, which is too late for the stream's first event to
        // have landed yet. Forcing eager creation here lets `pumpAndSettle`
        // below actually flush that first event before any tap.
        ChangeNotifierProvider(
          create: (_) => AuthProvider(_FakeSignedInAuthService()),
          lazy: false,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SettingsScreen.handlePhotoDescriptionsToggle(
                  context, settings, enable),
              child: const Text('toggle'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const uid = _FakeSignedInAuthService._user;

  testWidgets('flipping the toggle ON shows the consent sheet', (tester) async {
    await pump(tester, enable: true);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(find.text('Describe photos?'), findsOneWidget);
    expect(find.byKey(const Key('analysis-consent-allow')), findsOneWidget);
  });

  testWidgets(
      'declining the sheet leaves consent unset — the switch reads OFF '
      'because nothing was ever persisted', (tester) async {
    await pump(tester, enable: true);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(settings.analysisConsentUid, isNull);
    expect(settings.analysisConsentVersion, isNull);
    expect(settings.isAnalysisConsentedFor(uid.uid), isFalse);
  });

  testWidgets('allowing the sheet persists uid AND the current version',
      (tester) async {
    await pump(tester, enable: true);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('analysis-consent-allow')));
    await tester.pumpAndSettle();

    expect(settings.analysisConsentUid, uid.uid);
    expect(settings.analysisConsentVersion, kCurrentConsentVersion);
    expect(settings.isAnalysisConsentedFor(uid.uid), isTrue);
  });

  testWidgets(
      'a v1 (photo-only) consenter flipping ON is shown the sheet again, '
      'never silently upgraded', (tester) async {
    // Simulates an account that agreed to the OLD, narrower disclosure.
    await settings.setAnalysisConsent(uid.uid, version: 1);
    expect(settings.isAnalysisConsentedFor(uid.uid), isFalse,
        reason: 'a stale version must already read as unconsented');

    await pump(tester, enable: true);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    // The sheet — today's disclosure — is shown rather than the switch
    // silently flipping to consented under the OLD version.
    expect(find.text('Describe photos?'), findsOneWidget);
    expect(settings.analysisConsentVersion, 1,
        reason: 'must not be upgraded before Allow is tapped');

    await tester.tap(find.byKey(const Key('analysis-consent-allow')));
    await tester.pumpAndSettle();

    expect(settings.analysisConsentVersion, kCurrentConsentVersion);
  });

  testWidgets('turning the toggle OFF clears consent directly, with no sheet',
      (tester) async {
    await settings.setAnalysisConsent(uid.uid);
    expect(settings.isAnalysisConsentedFor(uid.uid), isTrue);

    await pump(tester, enable: false);
    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(find.text('Describe photos?'), findsNothing);
    expect(settings.analysisConsentUid, isNull);
    expect(settings.analysisConsentVersion, isNull);
  });
}
