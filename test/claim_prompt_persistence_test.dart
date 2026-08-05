import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

/// Drives the signed-in user, so a test can sign one account out and another
/// in WITHOUT rebuilding the widget tree — the same-session account switch
/// Settings' sign-out button now makes reachable.
class _FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => null;

  void emit(AppUser? user) => _controller.add(user);
  void dispose() => _controller.close();

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
  late _FakeAuthService auth;

  /// The persisted claim decision, shared by every read/write in one test.
  ClaimRecord? claimStore;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _FakeAuthService();
    claimStore = null;
    // Local data that predates any account -- the exact upgrade scenario the
    // claim prompt exists for.
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 5),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
  });

  tearDown(() async {
    auth.dispose();
    await db.close();
  });

  SyncTrigger buildTrigger({Future<ClaimRecord?> Function()? readClaim}) =>
      SyncTrigger(
        db,
        readClaim: readClaim ?? (() async => claimStore),
        writeClaim: (record) async => claimStore = record,
      );

  /// Mirrors `main.dart`: the trigger is told who is signed in on every
  /// signed-in rebuild, ABOVE `AppGate`. Without this the trigger's `_uid` is
  /// null and `resolveClaim` silently writes nothing, which would make these
  /// tests read as end-to-end proof while proving nothing.
  Widget wrap(SyncTrigger trigger) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          // `lazy: false` is load-bearing for the DISCRIMINATION of the tests
          // below, not for the app. A lazy SettingsProvider is not created
          // until `AppGate.build` reaches its `context.watch`, which happens
          // AFTER `_maybePromptClaim` has already scheduled its post-frame
          // callback -- so `load()` had not completed when that callback ran,
          // and any gate keyed on settings (e.g. the old device-global
          // `lastSyncedAt` check) read null and was never taken. The file then
          // passed 9/9 with the pre-fix AppGate body restored verbatim. Eager
          // creation makes the settings genuinely loaded by then, so a
          // reintroduced device-global gate really does suppress the prompt and
          // the test really does fail.
          ChangeNotifierProvider(
            lazy: false,
            create: (_) => SettingsProvider(SettingsRepository(db))..load(),
          ),
          ChangeNotifierProvider<SyncTrigger>.value(value: trigger),
        ],
        child: MaterialApp(
          home: Consumer<AuthProvider>(
            builder: (context, a, _) {
              context.read<SyncTrigger>().setUser(a.user?.uid);
              return const AppGate();
            },
          ),
        ),
      );

  Future<SyncTrigger> signIn(
    WidgetTester tester,
    String uid, {
    Future<ClaimRecord?> Function()? readClaim,
  }) async {
    final trigger = buildTrigger(readClaim: readClaim);
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(trigger));
    auth.emit(AppUser(uid: uid, email: '$uid@example.com'));
    await tester.pumpAndSettle();
    return trigger;
  }

  final claimSheet = find.byKey(const Key('claim.upload'));

  testWidgets('shows the prompt when this uid has never been asked',
      (tester) async {
    await signIn(tester, 'uid-1');

    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'does NOT re-show the prompt once this uid is on record as declined '
      '(persists across a simulated relaunch)', (tester) async {
    claimStore = const ClaimRecord(uid: 'uid-1', declined: true);

    await signIn(tester, 'uid-1');

    expect(claimSheet, findsNothing);
  });

  testWidgets('does NOT re-show the prompt once this uid has already claimed '
      'this device -- an answer either way is an answer', (tester) async {
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);

    await signIn(tester, 'uid-1');

    expect(claimSheet, findsNothing);
  });

  testWidgets(
      'DOES re-show the prompt for a different uid even though another uid '
      'declined -- that account has never been asked', (tester) async {
    claimStore = const ClaimRecord(uid: 'uid-1', declined: true);

    await signIn(tester, 'uid-2');

    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'asks a NEW account even though this DEVICE has already synced -- '
      'lastSyncedAt is device-global and must not answer for uid-2',
      (tester) async {
    // uid-1 claimed this device and synced: `lastSyncedAt` is now set forever,
    // which is exactly what the old gate keyed on.
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
      AppSettingsCompanion(lastSyncedAt: Value(DateTime(2026, 1, 6))),
    );

    await signIn(tester, 'uid-2');

    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'asks about health SETTINGS on a device with no logged days at all -- '
      'the settings document syncs too', (tester) async {
    // Without this the gate and the prompt both keyed on `dailyLogs` alone,
    // so a local-only user in pregnancy mode who had not logged days synced
    // `users/{uid}/settings/current` -- `pregnancyStartDate` included -- with
    // no prompt, and recorded an `uploaded` consent they were never asked for.
    await db.delete(db.dailyLogs).go();
    await SettingsRepository(db).update(
      AppSettingsCompanion(pregnancyStartDate: Value(DateTime(2026, 1, 1))),
    );

    await signIn(tester, 'uid-1');

    expect(claimSheet, findsOneWidget);
    // The copy must not claim "0 days logged" -- that misdescribes exactly
    // the data being offered up.
    expect(find.textContaining('0 days'), findsNothing);
    expect(find.textContaining('health settings'), findsOneWidget);
  });

  testWidgets('a device with nothing local at all is not asked', (tester) async {
    // The other half of the settings case: broadening the gate must not start
    // interrogating a brand-new user who has nothing to claim. `settingsUpdatedAt`
    // is stamped only by a real `SettingsRepository.update`, and this row has
    // never had one.
    await db.delete(db.dailyLogs).go();

    await signIn(tester, 'uid-2');

    expect(claimSheet, findsNothing);
  });

  testWidgets(
      'declining records the decline for the SIGNED-IN uid and holds the '
      'sync gate', (tester) async {
    final trigger = await signIn(tester, 'uid-1');

    await tester.tap(find.byKey(const Key('claim.keepLocal')));
    await tester.pumpAndSettle();

    expect(claimStore, const ClaimRecord(uid: 'uid-1', declined: true));
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets(
      'a same-session account switch asks the new account: uid-1 declines, '
      'signs out, uid-2 signs in and IS prompted', (tester) async {
    final trigger = await signIn(tester, 'uid-1');
    await tester.tap(find.byKey(const Key('claim.keepLocal')));
    await tester.pumpAndSettle();
    expect(claimSheet, findsNothing);

    auth.emit(null); // sign out -- local data is untouched
    await tester.pumpAndSettle();
    auth.emit(const AppUser(uid: 'uid-2', email: 'uid-2@example.com'));
    await tester.pumpAndSettle();

    expect(claimSheet, findsOneWidget);
    // And uid-2's own answer is recorded against uid-2, not uid-1.
    await tester.tap(find.byKey(const Key('claim.upload')));
    await tester.pumpAndSettle();
    expect(claimStore, const ClaimRecord(uid: 'uid-2', declined: false));
    expect(trigger.isPendingClaim, isFalse);
  });

  testWidgets(
      'a dismissed prompt is NOT a decline: nothing is persisted and the '
      'sync gate stays closed', (tester) async {
    final trigger = await signIn(tester, 'uid-1');
    expect(claimSheet, findsOneWidget);

    // The sheet blocks the system back button, but a dismissal must still be
    // safe if one ever gets through: `showModalBottomSheet` completes with
    // null, which is "no answer yet", never "declined".
    Navigator.of(tester.element(claimSheet)).pop();
    await tester.pumpAndSettle();

    expect(claimSheet, findsNothing);
    expect(claimStore, isNull);
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets('a failing claim-storage read still shows the prompt',
      (tester) async {
    // `flutter_secure_storage` can throw (a locked/absent keystore). This is
    // the one such call on this path outside `SyncTrigger.setUser`'s own
    // try/catch, and it runs inside an `addPostFrameCallback` closure, where
    // an escaping exception is an unhandled async error: the prompt would
    // never appear and the sync gate would stay closed forever, silently.
    await signIn(
      tester,
      'uid-1',
      readClaim: () async => throw Exception('keystore unavailable'),
    );

    expect(claimSheet, findsOneWidget);
  });
}
