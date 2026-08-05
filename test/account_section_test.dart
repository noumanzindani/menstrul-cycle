import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/auth/auth_error_text.dart';
import 'package:menstrul_track/screens/settings/account_section.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

/// A controllable fake so tests can assert exactly which auth actions ran
/// (and, critically, which did NOT run when a cloud step fails).
class _FakeAuthService implements AuthService {
  _FakeAuthService(this._user);
  AppUser? _user;
  bool signOutCalled = false;
  bool deleteAccountCalled = false;

  /// When set, `signOut` throws it — the shape of the blocker this round
  /// fixes: an auth call failing with nothing surfaced to the user.
  AuthFailure? signOutFailure;

  final _controller = StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _user;
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {
    signOutCalled = true;
    if (signOutFailure != null) throw signOutFailure!;
    _user = null;
    _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
  }

  void dispose() => _controller.close();
}

/// Records the order of the deletion calls, and can fail or hang on demand.
class _RecordingDeletionService extends AccountDeletionService {
  _RecordingDeletionService({
    required super.firestore,
    required super.uid,
    required this.calls,
    this.failRequest = false,
    this.hangRequest = false,
  });

  final List<String> calls;
  final bool failRequest;
  final bool hangRequest;

  @override
  Future<void> requestDeletion({DateTime? now}) async {
    calls.add('request');
    if (hangRequest) {
      // Exactly what an offline `WriteBatch.commit()` / `set()` does: the
      // future never completes and no exception is ever thrown.
      return Completer<void>().future;
    }
    if (failRequest) throw Exception('no network');
    return super.requestDeletion(now: now);
  }

  @override
  Future<void> cancelDeletion() {
    calls.add('cancel');
    return super.cancelDeletion();
  }
}

/// Records `suspend`/`resume` so the ORDER against the Firestore write can be
/// asserted, not just the fact that they happened.
class _SpySyncTrigger extends SyncTrigger {
  _SpySyncTrigger(
    super.db, {
    required this.calls,
    super.firestore,
    super.deviceId,
    super.readClaim,
    super.writeClaim,
  });

  final List<String> calls;

  @override
  Future<void> suspend() {
    calls.add('suspend');
    return super.suspend();
  }

  @override
  Future<void> resume() {
    calls.add('resume');
    return super.resume();
  }
}

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late _FakeAuthService authService;
  late List<String> calls;
  late ClaimRecord? storedClaim;
  late bool pinCleared;
  late bool notificationsCancelled;
  late bool claimPreferenceCleared;

  const user = AppUser(uid: 'uid-1', email: 'a@b.com');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    authService = _FakeAuthService(user);
    calls = [];
    storedClaim = null;
    pinCleared = false;
    notificationsCancelled = false;
    claimPreferenceCleared = false;
  });

  tearDown(() {
    authService.dispose();
    return db.close();
  });

  SyncTrigger buildTrigger({FirebaseFirestore Function()? triggerFirestore}) =>
      _SpySyncTrigger(
        db,
        calls: calls,
        firestore: triggerFirestore ?? (() => firestore),
        deviceId: () async => 'device-1',
        readClaim: () async => storedClaim,
        writeClaim: (record) async => storedClaim = record,
      );

  Widget wrap({
    SyncTrigger? trigger,
    bool failRequest = false,
    bool hangRequest = false,
    Duration requestTimeout = const Duration(seconds: 20),
  }) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(SettingsRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => MedicationProvider(MedicationRepository(db))..load(),
        ),
        ChangeNotifierProvider<SyncTrigger>.value(
          value: trigger ?? buildTrigger(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AccountSection(
            deletionService: (uid) => _RecordingDeletionService(
              firestore: firestore,
              uid: uid,
              calls: calls,
              failRequest: failRequest,
              hangRequest: hangRequest,
            ),
            requestTimeout: requestTimeout,
            // The real implementations of these three hit
            // flutter_secure_storage / the notification plugin, whose platform
            // channels have no handler under flutter_tester on this host (see
            // the doc comments on AccountSection's parameters).
            clearDeclinedPreference: () async => claimPreferenceCleared = true,
            clearPin: () async => pinCleared = true,
            cancelNotifications: () async => notificationsCancelled = true,
          ),
        ),
      ),
    );
  }

  Future<void> seedLocalDay(DateTime date) => DailyLogRepository(db).upsert(
        date: date,
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

  Future<void> tapDelete(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('account.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.confirmDelete')));
  }

  testWidgets('shows the signed-in email', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('a@b.com'), findsOneWidget);
  });

  testWidgets('sign out calls through to the auth service', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account.signOut')));
    await tester.pumpAndSettle();

    expect(authService.signOutCalled, isTrue);
  });

  testWidgets(
      'signing out NEVER wipes local data -- the local-first invariant, which '
      'had no guard at all', (tester) async {
    await seedLocalDay(DateTime(2026, 1, 1));
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account.signOut')));
    await tester.pumpAndSettle();

    expect(await DailyLogRepository(db).getAll(), hasLength(1));
    // And the in-memory mirror the UI renders from, which a wipe would also
    // have to have emptied.
    expect(
      (await DailyLogRepository(db).getForDate(DateTime(2026, 1, 1)))!.flow,
      FlowIntensity.medium,
    );
  });

  group('requesting deletion', () {
    testWidgets('cancelling the dialog changes nothing', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(await DailyLogRepository(db).getAll(), hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        'the confirm dialog says the device is erased NOW, the server copy '
        'later, and names the window', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account.delete')));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('this device')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('30 days')),
        findsWidgets,
      );
      // It must NOT claim the server data is already gone.
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('cancel'),
        ),
        findsWidgets,
      );
    });

    testWidgets(
        'records the marker, wipes the device, clears the PIN and every '
        'scheduled notification, and signs out -- but deletes NOTHING in the '
        'cloud and never deletes the auth user', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await firestore
          .collection('users/uid-1/dailyLogs')
          .doc('2026-01-01')
          .set({'date': '2026-01-01'});

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tapDelete(tester);
      await tester.pumpAndSettle();

      expect(
        (await firestore.doc('deletionRequests/uid-1').get()).exists,
        isTrue,
      );
      // Soft delete: the cloud copy has to survive, or "cancel" could not
      // give it back.
      expect(
        (await firestore.collection('users/uid-1/dailyLogs').get()).docs,
        hasLength(1),
      );
      expect(await DailyLogRepository(db).getAll(), isEmpty);
      expect(pinCleared, isTrue);
      expect(notificationsCancelled, isTrue);
      expect(claimPreferenceCleared, isTrue);
      expect(authService.signOutCalled, isTrue);
      expect(authService.deleteAccountCalled, isFalse);
    });

    testWidgets(
        'sync is suspended BEFORE the marker is written, so nothing this '
        'device holds can reach the account being deleted', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tapDelete(tester);
      await tester.pumpAndSettle();

      expect(calls, ['suspend', 'request']);
    });

    testWidgets(
        'a failed request aborts before anything local is touched, says so, '
        'and resumes sync', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap(failRequest: true));
      await tester.pumpAndSettle();

      await tapDelete(tester);
      await tester.pumpAndSettle();

      expect(await DailyLogRepository(db).getAll(), hasLength(1));
      expect(pinCleared, isFalse);
      expect(notificationsCancelled, isFalse);
      expect(authService.signOutCalled, isFalse);
      expect(find.textContaining("Couldn't"), findsOneWidget);
      expect(calls, ['suspend', 'request', 'resume']);
    });

    testWidgets(
        'an offline request reports a timeout instead of hanging forever '
        'behind a live UI', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap(
        hangRequest: true,
        requestTimeout: const Duration(seconds: 5),
      ));
      await tester.pumpAndSettle();

      await tapDelete(tester);
      await tester.pump(); // dialog closes, progress opens
      await tester.pump();

      // The UI is blocked while the destructive network op is in flight.
      expect(find.byKey(const Key('account.deleteProgress')), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.deleteProgress')), findsNothing);
      expect(find.textContaining('connection'), findsOneWidget);
      expect(await DailyLogRepository(db).getAll(), hasLength(1));
      expect(authService.signOutCalled, isFalse);
      expect(calls, ['suspend', 'request', 'resume']);
    });

    testWidgets('a second tap cannot start a second run', (tester) async {
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap(
        hangRequest: true,
        requestTimeout: const Duration(seconds: 30),
      ));
      await tester.pumpAndSettle();

      await tapDelete(tester);
      await tester.pump();
      await tester.pump();

      // The modal progress is what blocks it; tapping where the tile is must
      // not reach it.
      await tester.tap(
        find.byKey(const Key('account.delete')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // It must not even reach the confirmation, let alone a second write.
      expect(find.byKey(const Key('account.confirmDelete')), findsNothing);
      expect(calls.where((c) => c == 'request'), hasLength(1));

      // Let the request's own timeout fire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a sign-out failure after the request is SURFACED with the real '
        'message and a retry, never swallowed', (tester) async {
      authService.signOutFailure = AuthFailure(AuthErrorCode.requiresRecentLogin);
      await seedLocalDay(DateTime(2026, 1, 1));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tapDelete(tester);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          messageForAuthError(AuthErrorCode.requiresRecentLogin),
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      // The request itself still stands -- the user must not be told the
      // whole thing failed when the deletion IS recorded.
      expect(
        (await firestore.doc('deletionRequests/uid-1').get()).exists,
        isTrue,
      );
    });
  });

  group('a pending request during the grace window', () {
    testWidgets(
        'replaces the delete control with a notice naming the purge date and '
        'a way out', (tester) async {
      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: DateTime(2026, 8, 5));

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.deletionPending')), findsOneWidget);
      expect(find.byKey(const Key('account.delete')), findsNothing);
      expect(find.textContaining('September 4, 2026'), findsOneWidget);
    });

    testWidgets('cancelling it withdraws the request', (tester) async {
      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: DateTime(2026, 8, 5));

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account.cancelDeletion')));
      await tester.pumpAndSettle();

      expect(
        (await firestore.doc('deletionRequests/uid-1').get()).exists,
        isFalse,
      );
      expect(find.byKey(const Key('account.deletionPending')), findsNothing);
      expect(find.byKey(const Key('account.delete')), findsOneWidget);
    });
  });

  group('the cloud-sync status tile', () {
    testWidgets(
        'an account that has never answered the claim question is reported '
        'OFF -- "not declined" is not the same as "syncing"', (tester) async {
      storedClaim = null; // no decision on record for anyone

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.enableSync')), findsOneWidget);
      expect(find.byKey(const Key('account.syncStatus')), findsNothing);
    });

    testWidgets('an account that claimed this device is reported ON',
        (tester) async {
      storedClaim = const ClaimRecord(uid: 'uid-1', declined: false);
      // A trigger that is genuinely signed in and past the claim gate, not
      // merely one with a favourable record on disk: "is sync on" is a
      // question about this device's live state, and `isSyncEnabledFor`'s
      // semantics are being tightened to say so.
      final trigger = buildTrigger();
      await trigger.setUser('uid-1');

      await tester.pumpWidget(wrap(trigger: trigger));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.syncStatus')), findsOneWidget);
      expect(find.byKey(const Key('account.enableSync')), findsNothing);
    });

    testWidgets('another account\'s record never reports THIS one as on',
        (tester) async {
      storedClaim = const ClaimRecord(uid: 'other-uid', declined: false);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.enableSync')), findsOneWidget);
      expect(find.byKey(const Key('account.syncStatus')), findsNothing);
    });

    testWidgets(
        'turning sync on records the reversal AND actually uploads -- not '
        'merely a local setState', (tester) async {
      storedClaim = const ClaimRecord(uid: 'uid-1', declined: true);
      await seedLocalDay(DateTime(2026, 1, 1));

      final trigger = buildTrigger();
      await trigger.setUser('uid-1');
      expect(trigger.isPendingClaim, isTrue, reason: 'declined => gated');

      await tester.pumpWidget(wrap(trigger: trigger));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account.enableSync')), findsOneWidget);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      // 1. the persisted decision really flipped
      expect(storedClaim!.declined, isFalse);
      expect(storedClaim!.uid, 'uid-1');
      // 2. a sync really ran: the local day is now in Firestore
      expect(
        (await firestore.doc('users/uid-1/dailyLogs/2026-01-01').get()).exists,
        isTrue,
      );
      // 3. and only then does the tile flip
      expect(find.byKey(const Key('account.syncStatus')), findsOneWidget);
    });

    testWidgets(
        'turning sync on while offline says nothing synced, instead of '
        'reporting success', (tester) async {
      storedClaim = const ClaimRecord(uid: 'uid-1', declined: true);
      await seedLocalDay(DateTime(2026, 1, 1));

      final trigger = buildTrigger(
        triggerFirestore: () => throw Exception('no Firebase'),
      );
      await trigger.setUser('uid-1');

      await tester.pumpWidget(wrap(trigger: trigger));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.textContaining("hasn't synced"), findsOneWidget);
    });
  });
}
