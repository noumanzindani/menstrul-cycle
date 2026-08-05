import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/settings_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Settings → "Delete all my data".
///
/// This control used to empty the device and then let the very next sync refill
/// it from the cloud, because `deleteAllData` nulls `lastSyncedAt` and a null
/// `since` makes the next run a FULL sweep. It was the one destructive control
/// in the app that silently undid itself. It now also turns cloud sync OFF for
/// the signed-in account on this device, and clears Firestore's own on-device
/// cache — which drift's encryption never covered.
class _FakeSignedInAuthService implements AuthService {
  static const _user = AppUser(uid: 'uid-1', email: 'a@b.com');

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

void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late PremiumProvider premium;
  late LogProvider logs;
  late MedicationProvider meds;
  late SyncTrigger trigger;

  /// Stands in for `ClaimPreference`'s keystore-backed storage.
  ClaimRecord? claimStore;
  late List<String> calls;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    // No premium.load(): that opens an in_app_purchase platform channel that
    // is not available under flutter_test (mirrors the other Settings tests).
    premium = PremiumProvider(SettingsRepository(db));
    logs = LogProvider(DailyLogRepository(db));
    await logs.load();
    meds = MedicationProvider(MedicationRepository(db));
    await meds.load();
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
    calls = [];
    trigger = SyncTrigger(
      db,
      // No `firestore:` override — the default `lunaFirestore()` throws with
      // no Firebase app, which `setUser` catches and leaves `_service` null.
      // Nothing here needs a live sync; what is under test is the GATE.
      deviceId: () async => 'device-1',
      readClaim: () async => claimStore,
      writeClaim: (record) async => claimStore = record,
    );
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>.value(value: premium),
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<MedicationProvider>.value(value: meds),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(_FakeSignedInAuthService()),
        ),
        ChangeNotifierProvider<SyncTrigger>.value(value: trigger),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          // All three real implementations are platform-channel backed;
          // `flutter_secure_storage` in particular HANGS under flutter_tester
          // on this host rather than throwing, and `pumpAndSettle` does not
          // detect a stalled channel call. See the doc comments on
          // `SettingsScreen`'s parameters.
          clearPin: () async => calls.add('clearPin'),
          cancelNotifications: () async => calls.add('cancelNotifications'),
          clearFirestoreCache: () async => calls.add('clearCache'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> seedDay(DateTime date) => DailyLogRepository(db).upsert(
        date: date,
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

  Future<void> tapDeleteAll(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    // `dragUntilVisible` stops on the frame its finder first matches, which
    // leaves the tile right at the viewport edge — `tap` then lands outside it
    // (the hazard `settings_backup_test.dart` documents). Scrolling PAST it
    // instead is not an option either: this is a lazy list, so the tile is
    // unbuilt again. So: bring it on screen, then nudge it clear of the edge.
    await tester.dragUntilVisible(
      find.text('Delete all my data'),
      scrollable,
      const Offset(0, -300),
    );
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all my data'));
    await tester.pumpAndSettle();
    // By key, not by label: the confirm button's copy is itself under test
    // below, and this helper must not have to change when it does.
    await tester.tap(find.byKey(const Key('settings.confirmDeleteAll')));
    await tester.pumpAndSettle();
  }

  testWidgets('the wipe clears local data, the PIN and every notification',
      (tester) async {
    await seedDay(DateTime(2026, 1, 1));
    await pump(tester);

    await tapDeleteAll(tester);

    expect(await DailyLogRepository(db).getAll(), isEmpty);
    expect(calls, contains('clearPin'));
    expect(calls, contains('cancelNotifications'));
  });

  testWidgets(
      "Firestore's on-device cache is cleared too -- drift is encrypted at "
      'rest, the SDK cache is not, and it holds the same health documents',
      (tester) async {
    await seedDay(DateTime(2026, 1, 1));
    await pump(tester);

    await tapDeleteAll(tester);

    expect(calls, contains('clearCache'));
  });
}
