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

/// Settings → Health context: the Tier 1 clinical profile (contraception and
/// when it started, diagnoses already given, breastfeeding and since-date).
///
/// What these tests are strict about is the THREE-STATE rule. Every field here
/// distinguishes "never asked" from a real answer, and for contraception the
/// two real answers are not symmetric either: `contra_none` says the user uses
/// nothing, while null says nobody asked. A screen that collapsed them would
/// print an invented clinical fact in the doctor report.
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

  /// Cycle regularity lives in the "Cycle defaults" group beside the two
  /// length steppers, not in the clinical group above — but it is the same
  /// three-state rule, and it is the ONLY way a user who upgraded can answer a
  /// question the wizard never asked her. The v13 migration backfills nothing
  /// on purpose, so without this row an upgraded install is stuck at "nobody
  /// asked" forever.
  group('cycle regularity', () {
    const rowTitle = 'How much your cycle varies';

    /// Same lazy-ListView trap the clinical group documents above: this row
    /// sits further down again, so nothing is BUILT until it is scrolled to.
    Future<void> reveal(WidgetTester tester) async {
      await tester.dragUntilVisible(find.text(rowTitle),
          find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }

    testWidgets('reads as unanswered until it is answered', (tester) async {
      await pump(tester);
      await reveal(tester);
      expect(rowValue(rowTitle, 'Not answered'), findsOneWidget);
    });

    testWidgets('an answer is stored and shown back', (tester) async {
      await pump(tester);
      await reveal(tester);
      await tapRow(tester, rowTitle);
      await tester.tap(find.text('It varies a lot').last);
      await tester.pumpAndSettle();

      expect((await db.getSettings()).cycleRegularity, kRegularityIrregular);
      expect(rowValue(rowTitle, 'It varies a lot'), findsOneWidget);
    });

    testWidgets('it can be put back to unanswered', (tester) async {
      await settings.setCycleRegularity(kRegularityVeryRegular);
      await pump(tester);
      await reveal(tester);

      await tapRow(tester, rowTitle);
      await tester.tap(find.text('Not answered').last);
      await tester.pumpAndSettle();

      expect((await db.getSettings()).cycleRegularity, isNull,
          reason: 'a user who realises she guessed must be able to withdraw '
              'the guess, not only replace it with another');
    });
  });

  /// The only route to this answer for a user who UPGRADED (v14 backfills
  /// nothing), and the way to fill in later what signup declined.
  group('recent pregnancy', () {
    const rowTitle = 'Pregnant in the last 3 months';

    DateTime today() {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day);
    }

    Future<void> reveal(WidgetTester tester) async {
      await tester.dragUntilVisible(find.text(rowTitle),
          find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }

    testWidgets('reads as unanswered until it is answered', (tester) async {
      await pump(tester);
      await reveal(tester);
      expect(rowValue(rowTitle, 'Not answered'), findsOneWidget);
    });

    testWidgets('"No" is stored with today\'s date and shown back',
        (tester) async {
      await pump(tester);
      await tapRow(tester, rowTitle);
      await tester.tap(find.text('No').last);
      await tester.pumpAndSettle();

      final s = await db.getSettings();
      expect(s.pregnancyStatus, kPregnancyNone);
      expect(s.pregnancyStatusDate, today());
      expect(rowValue(rowTitle, 'No'), findsOneWidget);
    });

    testWidgets('a birth asks how long ago and stores the event date',
        (tester) async {
      await pump(tester);
      await tapRow(tester, rowTitle);
      await tester.tap(find.text('Yes, I gave birth').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 weeks ago').last);
      await tester.pumpAndSettle();

      final s = await db.getSettings();
      final t = today();
      expect(s.pregnancyStatus, kPregnancyBirth);
      expect(s.pregnancyStatusDate, DateTime(t.year, t.month, t.day - 21));
      expect(rowValue(rowTitle, 'Gave birth'), findsOneWidget);
    });

    testWidgets('dismissing the weeks question changes nothing',
        (tester) async {
      await settings.setPregnancyStatus(kPregnancyNone, date: today());
      await pump(tester);
      await tapRow(tester, rowTitle);
      await tester.tap(find.text('Yes, a miscarriage or ended pregnancy').last);
      await tester.pumpAndSettle();
      // Tap outside the dialog.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect((await db.getSettings()).pregnancyStatus, kPregnancyNone,
          reason: 'a loss without its date is half an answer; keep the old one');
    });

    testWidgets('it can be put back to unanswered', (tester) async {
      await settings.setPregnancyStatus(kPregnancyNow, date: today());
      await pump(tester);
      await tapRow(tester, rowTitle);
      await tester.tap(find.text('Not answered').last);
      await tester.pumpAndSettle();

      final s = await db.getSettings();
      expect(s.pregnancyStatus, isNull);
      expect(s.pregnancyStatusDate, isNull);
    });
  });

  group('puberty', () {
    const bTitle = 'Breast development (B stage)';
    const pTitle = 'Pubic hair (P stage)';
    const tTitle = 'Puberty timing';

    Future<void> reveal(WidgetTester tester, String title) async {
      await tester.dragUntilVisible(find.text(title),
          find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }

    testWidgets('the rows read as unanswered until answered', (tester) async {
      await pump(tester);
      await reveal(tester, tTitle);
      expect(rowValue(bTitle, 'Not answered'), findsOneWidget);
      expect(rowValue(pTitle, 'Not answered'), findsOneWidget);
      expect(rowValue(tTitle, 'Not answered'), findsOneWidget);
    });

    testWidgets('picking a B stage stores its key and today, shown as "B3"',
        (tester) async {
      await pump(tester);
      await tapRow(tester, bTitle);
      await tester.tap(find.text('B3 · Growing').last);
      await tester.pumpAndSettle();

      final s = await db.getSettings();
      final n = DateTime.now();
      expect(s.breastStage, 'tan_b3');
      expect(s.pubertyAnsweredOn, DateTime(n.year, n.month, n.day));
      expect(rowValue(bTitle, 'B3'), findsOneWidget);
    });

    testWidgets("the timing row shows the answer and the app's reading",
        (tester) async {
      final n = DateTime.now();
      await settings.setBreastStage('tan_b5', answeredOn: n);
      await settings.setPubicHairStage('tan_p2', answeredOn: n);
      await pump(tester);
      await tapRow(tester, tTitle);
      await tester.tap(find.text('Out of step (discordant)').last);
      await tester.pumpAndSettle();

      expect((await db.getSettings()).pubertyTiming, 'pub_discordant');
      expect(rowValue(tTitle, 'Discordant'), findsOneWidget);
      expect(find.textContaining('B and P out of step'), findsOneWidget);
    });

    testWidgets('a stage can be put back to unanswered', (tester) async {
      await settings.setPubicHairStage('tan_p4', answeredOn: DateTime.now());
      await pump(tester);
      await tapRow(tester, pTitle);
      await tester.tap(find.text('Not answered').last);
      await tester.pumpAndSettle();
      expect((await db.getSettings()).pubicHairStage, isNull);
    });
  });

  testWidgets('every clinical row reads as unanswered until it is answered',
      (tester) async {
    await pump(tester);
    // The ListView is lazy, so a row below the fold is not BUILT — an
    // assertion here without scrolling first would pass against a screen that
    // renders nothing at all.
    await tester.dragUntilVisible(find.text('Breastfeeding'),
        find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(rowValue('Contraception', 'Not answered'), findsOneWidget);
    expect(rowValue('Diagnoses', 'None recorded'), findsOneWidget);
    expect(rowValue('Breastfeeding', 'Not answered'), findsOneWidget);

    // Nothing is written by merely rendering the screen.
    final row = await SettingsRepository(db).get();
    expect(row.contraceptionMethod, isNull);
    expect(row.knownDiagnoses, isNull);
    expect(row.breastfeeding, isNull);
  });

  testWidgets('picking a method stores its stable key, not its label',
      (tester) async {
    await pump(tester);
    await tapRow(tester, 'Contraception');
    await tester.tap(find.text('Combined pill'));
    await tester.pumpAndSettle();

    expect((await SettingsRepository(db).get()).contraceptionMethod,
        'contra_combined_pill');
    expect(rowValue('Contraception', 'Combined pill'), findsOneWidget);
  });

  testWidgets('a suppressing method says so on the row, a non-hormonal one '
      'does not', (tester) async {
    await pump(tester);
    await tapRow(tester, 'Contraception');
    await tester.tap(find.text('Combined pill'));
    await tester.pumpAndSettle();

    // The user is TOLD why their fertile window disappeared. An estimate that
    // silently vanishes is the same class of problem as one that is silently
    // wrong.
    expect(find.textContaining('Fertile-window estimates are paused'),
        findsOneWidget);

    await tapRow(tester, 'Contraception');
    await tester.tap(find.text('Copper IUD'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fertile-window estimates are paused'),
        findsNothing);
  });

  testWidgets('"None" is a real answer and is NOT treated as unanswered',
      (tester) async {
    await pump(tester);
    await tapRow(tester, 'Contraception');
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();

    expect((await SettingsRepository(db).get()).contraceptionMethod,
        kContraceptionNone);
    expect(rowValue('Contraception', 'None'), findsOneWidget);
    expect(rowValue('Contraception', 'Not answered'), findsNothing);
  });

  testWidgets('diagnoses are a multi-select stored as a JSON array',
      (tester) async {
    await pump(tester);
    await tapRow(tester, 'Diagnoses');
    await tester.tap(find.text('PCOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Endometriosis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = (await SettingsRepository(db).get()).knownDiagnoses;
    expect(stored, isNotNull);
    expect(stored, contains('dx_pcos'));
    expect(stored, contains('dx_endometriosis'));
    expect(rowValue('Diagnoses', '2 recorded'), findsOneWidget);
  });

  testWidgets('breastfeeding offers three states and reveals a since-date',
      (tester) async {
    await pump(tester);
    expect(find.text('Breastfeeding since'), findsNothing);

    await tapRow(tester, 'Breastfeeding');
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect((await SettingsRepository(db).get()).breastfeeding, isTrue);
    // The date row only exists once the answer makes it meaningful.
    expect(find.text('Breastfeeding since'), findsOneWidget);

    await tapRow(tester, 'Breastfeeding');
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    final row = await SettingsRepository(db).get();
    expect(row.breastfeeding, isFalse);
    expect(row.breastfeedingSince, isNull);
    expect(find.text('Breastfeeding since'), findsNothing);
  });

  testWidgets('the section says out loud that none of this is a diagnosis',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Health context'),
        find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.textContaining('never diagnoses'), findsOneWidget);
  });
}
