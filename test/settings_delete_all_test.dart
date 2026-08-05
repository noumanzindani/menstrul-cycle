import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

  /// A trigger with a LIVE (fake) Firestore behind it, so `_service` is
  /// non-null. That matters for anything asserting on `isSyncEnabledFor`: with
  /// the default `lunaFirestore()` (which throws on a build with no Firebase
  /// app) `_service` stays null and that getter answers `false` for a reason
  /// that has nothing to do with what is under test.
  SyncTrigger syncingTrigger(FakeFirebaseFirestore firestore) => SyncTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async => 'device-1',
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

  Future<void> pump(WidgetTester tester, {SyncTrigger? withTrigger}) async {
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
        ChangeNotifierProvider<SyncTrigger>.value(value: withTrigger ?? trigger),
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

  testWidgets(
      'the wipe HOLDS: sync is turned off for the signed-in account, so the '
      'next full sweep cannot refill the device from the cloud', (tester) async {
    await seedDay(DateTime(2026, 1, 1));
    await trigger.setUser('uid-1');
    await pump(tester);

    await tapDeleteAll(tester);

    // The durable half: the same uid-scoped record the claim prompt writes,
    // so `SyncTrigger.setUser` re-applies the gate on every future sign-in.
    expect(claimStore?.uid, 'uid-1');
    expect(claimStore?.declined, isTrue);
    // The session half: nothing can push or pull for this account right now.
    expect(await trigger.isSyncEnabledFor('uid-1'), isFalse);
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets(
      'it does NOT leave the trigger suspended -- Settings -> Account must '
      'still be able to turn sync back on', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final t = syncingTrigger(firestore);
    await seedDay(DateTime(2026, 1, 1));
    await t.setUser('uid-1');
    await pump(tester, withTrigger: t);

    await tapDeleteAll(tester);

    // A still-suspended trigger would record consent and then silently refuse
    // to sync: `syncNow()` no-ops while suspended, so "Turn on" would report
    // success against a device that never syncs again this session — and
    // `isSyncEnabledFor` (which the tile reads) would keep saying OFF forever.
    await seedDay(DateTime(2026, 2, 2));
    await t.resolveClaim(upload: true);

    expect(await t.isSyncEnabledFor('uid-1'), isTrue);
    // The honest end-to-end check: something actually left the device.
    expect(
      (await firestore.collection('users/uid-1/dailyLogs').get()).docs,
      isNotEmpty,
    );
  });

  testWidgets(
      'sync is stopped BEFORE the wipe, not after -- the wipe itself arms a '
      'sync via LogProvider', (tester) async {
    await seedDay(DateTime(2026, 1, 1));
    await trigger.setUser('uid-1');
    await pump(tester);

    // A spy that fails the test if the database is already empty when the
    // decline is recorded: ordering, not just occurrence.
    var localRowsWhenDeclined = -1;
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
    final probe = SyncTrigger(
      db,
      deviceId: () async => 'device-1',
      readClaim: () async => claimStore,
      writeClaim: (record) async {
        localRowsWhenDeclined = (await DailyLogRepository(db).getAll()).length;
        claimStore = record;
      },
    );
    await probe.setUser('uid-1');

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
        ChangeNotifierProvider<SyncTrigger>.value(value: probe),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          clearPin: () async => calls.add('clearPin'),
          cancelNotifications: () async => calls.add('cancelNotifications'),
          clearFirestoreCache: () async => calls.add('clearCache'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tapDeleteAll(tester);

    expect(localRowsWhenDeclined, 1);
  });

  testWidgets(
      'END TO END: the device stays empty across a later sync, and the cloud '
      'copy is still there to come back to', (tester) async {
    // The reviewer's own reproduction: local 0, then local 2 and cloud 2.
    // `deleteAllData` nulls `lastSyncedAt`, so the next run has `since == null`
    // and pulls the WHOLE cloud history back down.
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('users/uid-1/dailyLogs')
        .doc('2026-01-01')
        .set({'date': '2026-01-01', 'flow': 3, 'updatedAt': 1767225600000});
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
    final synced = SyncTrigger(
      db,
      firestore: () => firestore,
      deviceId: () async => 'device-1',
      readClaim: () async => claimStore,
      writeClaim: (record) async => claimStore = record,
    );
    await synced.setUser('uid-1');
    await synced.syncNow();
    await logs.load();
    expect(await DailyLogRepository(db).getAll(), isNotEmpty,
        reason: 'precondition: the cloud copy reaches this device at all');

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
        ChangeNotifierProvider<SyncTrigger>.value(value: synced),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          clearPin: () async => calls.add('clearPin'),
          cancelNotifications: () async => calls.add('cancelNotifications'),
          clearFirestoreCache: () async => calls.add('clearCache'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tapDeleteAll(tester);

    // Whatever the app does next — an app resume, a debounced write, a
    // relaunch — must not undo the wipe.
    await synced.syncNow();
    await synced.syncNow();

    expect(await DailyLogRepository(db).getAll(), isEmpty);
    // And the other half of the promise the dialog makes: the account still
    // has the user's history.
    expect(
      (await firestore.collection('users/uid-1/dailyLogs').get()).docs,
      hasLength(1),
    );
  });

  testWidgets(
      'the copy matches what the control actually does: device erased, sync '
      'off here, the server copy explicitly kept', (tester) async {
    await pump(tester);

    final scrollable = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.text('Delete all my data'),
      scrollable,
      const Offset(0, -300),
    );
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all my data'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.textContaining(text));

    expect(inDialog('on this device'), findsWidgets);
    expect(inDialog('turns cloud sync off'), findsWidgets);
    expect(inDialog('nothing is downloaded back'), findsWidgets);
    // The promise this control must NOT make. It leaves the account's cloud
    // copy alone, and the copy has to say so rather than implying erasure
    // everywhere — that is a different control, with a 30-day grace window.
    expect(inDialog('on our server are kept'), findsWidgets);
    expect(inDialog('Request account deletion'), findsWidgets);
    // And the confirm button no longer says "Delete everything", which is the
    // one thing it does not do.
    expect(find.text('Erase this device'), findsOneWidget);
    expect(find.text('Delete everything'), findsNothing);
  });
}
