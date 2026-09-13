import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
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

/// Reports an already-signed-in user — `AccountSection` sits above the Profile
/// group on this screen and reads `AuthProvider` (copied from
/// `settings_backup_test.dart`).
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

/// Settings → Profile: the four per-user profile fields (date of birth, height,
/// current weight, age at first period) are editable here and persist to the
/// single `AppSettings` row.
///
/// Two things these tests are deliberately strict about:
///
/// * **Canonical units are what get stored.** A height typed under the lb/ft
///   preference must land in the database as centimetres, never as inches.
/// * **Out of range is a REFUSAL.** Nothing is written, an inline error shows,
///   and the dialog stays open — the same contract as
///   `DayEntryFormState.save()`, never a silent clamp.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late PremiumProvider premium;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    // No premium.load() — that opens an in_app_purchase platform channel that
    // isn't available under flutter_test (mirrors the other settings harnesses).
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
        // Overridden claim hooks so AccountSection never touches the real
        // flutter_secure_storage plugin, which HANGS under flutter_tester on
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

  /// Brings a Profile row into view and taps it.
  ///
  /// `dragUntilVisible` alone is NOT enough here: it stops on the frame its
  /// finder matches, and this list is short enough that rows near the top are
  /// already built on frame 1 — so it scrolls nothing and the tap lands on
  /// whatever is actually at that y. `ensureVisible` is the call that moves the
  /// viewport (the note at settings_backup_test.dart:100-107).
  Future<void> tapRow(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.dragUntilVisible(
        target, find.byType(Scrollable).first, const Offset(0, -120));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The trailing value rendered on the row titled [title].
  Finder rowValue(String title, String value) => find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.text(value),
      );

  testWidgets('every profile row reads Not set until it is answered',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Age at first period'),
        find.byType(Scrollable).first, const Offset(0, -120));
    await tester.ensureVisible(find.text('Age at first period'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(rowValue('Date of birth', 'Not set'), findsOneWidget);
    expect(rowValue('Height', 'Not set'), findsOneWidget);
    expect(rowValue('Current weight', 'Not set'), findsOneWidget);
    expect(rowValue('Age at first period', 'Not set'), findsOneWidget);
  });

  testWidgets('date of birth picks a full date and persists it', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Date of birth');

    // The picker opens on its seed month (25 years back), so day 15 exists in
    // whatever month that is.
    expect(find.text('Your date of birth'), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expected = DateTime(now.year - 25, now.month, 15);
    final stored = await SettingsRepository(db).get();
    expect(stored.dateOfBirth, expected);
    expect(settings.dateOfBirth, expected);
    // ...and the row now shows it rather than "Not set".
    expect(rowValue('Date of birth', 'Not set'), findsNothing);
  });

  testWidgets('height saves in canonical centimetres and shows on the row',
      (tester) async {
    await pump(tester);
    await tapRow(tester, 'Height');

    await tester.enterText(
        find.byKey(const Key('settings.profile.heightField')), '165');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.heightCm, 165.0);
    expect(rowValue('Height', '165.0 cm'), findsOneWidget);
  });

  testWidgets('a height typed in feet and inches still stores centimetres',
      (tester) async {
    await settings.setWeightUnit(kWeightUnitLb);
    await pump(tester);
    await tapRow(tester, 'Height');

    await tester.enterText(
        find.byKey(const Key('settings.profile.heightField')), "5'5\"");
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.heightCm, closeTo(165.1, 0.05));
    expect(rowValue('Height', "5'5\""), findsOneWidget);
  });

  testWidgets('an out-of-range height is refused, not clamped', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Height');

    await tester.enterText(
        find.byKey(const Key('settings.profile.heightField')), '300');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Nothing written, an inline error showing, and the dialog still open so
    // the typed value is not lost.
    final stored = await SettingsRepository(db).get();
    expect(stored.heightCm, isNull);
    expect(find.text('Enter a height between 80.0 cm and 250.0 cm'),
        findsOneWidget);
    expect(find.byKey(const Key('settings.profile.heightField')),
        findsOneWidget);
  });

  testWidgets('clearing the height field clears the stored value',
      (tester) async {
    await settings.setHeightCm(170);
    await pump(tester);
    await tapRow(tester, 'Height');

    await tester.enterText(
        find.byKey(const Key('settings.profile.heightField')), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.heightCm, isNull);
    expect(rowValue('Height', 'Not set'), findsOneWidget);
  });

  testWidgets('current weight saves in canonical kilograms', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Current weight');

    await tester.enterText(
        find.byKey(const Key('settings.profile.weightField')), '62.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.profileWeightKg, 62.5);
    expect(rowValue('Current weight', '62.5 kg'), findsOneWidget);
  });

  testWidgets('a weight typed in pounds still stores kilograms',
      (tester) async {
    await settings.setWeightUnit(kWeightUnitLb);
    await pump(tester);
    await tapRow(tester, 'Current weight');

    await tester.enterText(
        find.byKey(const Key('settings.profile.weightField')), '140');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.profileWeightKg, closeTo(63.5, 0.05));
    expect(rowValue('Current weight', '140.0 lb'), findsOneWidget);
  });

  testWidgets('an out-of-range weight is refused, not clamped', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Current weight');

    await tester.enterText(
        find.byKey(const Key('settings.profile.weightField')), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.profileWeightKg, isNull);
    expect(find.text('Enter a weight between 20.0 kg and 350.0 kg'),
        findsOneWidget);
  });

  testWidgets(
      'the profile weight row is labelled apart from the per-day weight metric',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Current weight'),
        find.byType(Scrollable).first, const Offset(0, -120));
    await tester.ensureVisible(find.text('Current weight'));
    await tester.pumpAndSettle();

    // Never the bare word the day editor uses for its own field — these are two
    // different values and the UI must not let them read as one.
    expect(find.widgetWithText(ListTile, 'Weight'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Current weight'),
        matching: find.textContaining('separate from'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('age at first period steps and persists', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Age at first period');

    expect(find.text('13 years'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.profile.menarchePlus')));
    await tester.pumpAndSettle();
    expect(find.text('14 years'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.menarcheAge, 14);
    expect(rowValue('Age at first period', '14 years'), findsOneWidget);
  });

  testWidgets('the age stepper bounds by DISABLING, never by clamping',
      (tester) async {
    await pump(tester);
    await tapRow(tester, 'Age at first period');

    // 13 → 8 is five taps; the sixth must be impossible rather than ignored.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('settings.profile.menarcheMinus')));
      await tester.pumpAndSettle();
    }
    expect(find.text('8 years'), findsOneWidget);
    final minus = tester.widget<IconButton>(
        find.byKey(const Key('settings.profile.menarcheMinus')));
    expect(minus.onPressed, isNull);

    // ...and the same at the top of the range.
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byKey(const Key('settings.profile.menarchePlus')));
      await tester.pumpAndSettle();
    }
    expect(find.text('20 years'), findsOneWidget);
    final plus = tester.widget<IconButton>(
        find.byKey(const Key('settings.profile.menarchePlus')));
    expect(plus.onPressed, isNull);
  });

  testWidgets('a long date of birth still lays out at phone width',
      (tester) async {
    // The default 800x600 test surface is not a phone, which is exactly how the
    // off-screen FilledButton shipped (CLAUDE.md). A full date is the longest
    // value on this screen, so it is the one that can starve its row's title.
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await settings.setDateOfBirth(DateTime(2001, 9, 15));
    await pump(tester);

    expect(tester.takeException(), isNull);
    final tile = tester.getRect(find.widgetWithText(ListTile, 'Date of birth'));
    expect(tile.right, lessThanOrEqualTo(360.0));
  });

  testWidgets('cancelling a dialog writes nothing', (tester) async {
    await settings.setHeightCm(170);
    await pump(tester);
    await tapRow(tester, 'Height');

    await tester.enterText(
        find.byKey(const Key('settings.profile.heightField')), '181');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final stored = await SettingsRepository(db).get();
    expect(stored.heightCm, 170.0);
  });
}
