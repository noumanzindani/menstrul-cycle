import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/screens/onboarding/onboarding_screen.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// The sign-in-time deletion notice (`AppGate` → `DeletionPendingScreen`).
///
/// `deleteAllData()` resets `onboardingComplete`, so a user who requested
/// deletion and later signs back in inside the grace window got the FULL
/// onboarding flow for an account queued for erasure, and was told nothing —
/// Settings → Account was the only disclosure, and it is not on their path.
class _FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  bool signOutCalled = false;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => _user;
  void emit(AppUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {
    signOutCalled = true;
    emit(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
  void dispose() => _controller.close();
}

void main() {
  late AppDatabase db;
  late _FakeAuthService auth;
  late FakeFirebaseFirestore firestore;
  late List<String> cancelled;
  ClaimRecord? claimStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _FakeAuthService();
    firestore = FakeFirebaseFirestore();
    cancelled = [];
    // Recorded, so the account is not re-asked the claim question here: this
    // file is about the deletion notice, and the claim sheet's own sequencing
    // is covered by `claim_prompt_persistence_test.dart`.
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
  });

  tearDown(() async {
    auth.dispose();
    await db.close();
  });

  SyncTrigger buildTrigger() => SyncTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async => 'device-1',
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

  final pendingRequest = DeletionRequest(
    requestedAt: DateTime(2026, 8, 1),
    purgeAfter: DateTime(2026, 8, 31),
  );

  /// Mirrors `main.dart`: the trigger is told who is signed in ABOVE
  /// `AppGate`, so a `syncNow()` from the cancel path has a live service.
  Widget wrap(
    SyncTrigger trigger, {
    required Future<DeletionRequest?> Function(String uid) pendingDeletion,
    Future<void> Function(String uid)? cancelDeletion,
    Key? gateKey,
  }) =>
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          // `lazy: false` for the same discrimination reason
          // `claim_prompt_persistence_test.dart` documents: a lazy provider is
          // not created until `build` reaches its `watch`, which is after the
          // post-frame callbacks are scheduled.
          ChangeNotifierProvider(
            lazy: false,
            create: (_) => SettingsProvider(SettingsRepository(db))..load(),
          ),
          ChangeNotifierProvider(
            lazy: false,
            create: (_) => LogProvider(DailyLogRepository(db))..load(),
          ),
          ChangeNotifierProvider<SyncTrigger>.value(value: trigger),
        ],
        child: MaterialApp(
          home: Consumer<AuthProvider>(
            builder: (context, a, _) {
              context.read<SyncTrigger>().setUser(a.user?.uid);
              return AppGate(
                key: gateKey,
                pendingDeletion: pendingDeletion,
                cancelDeletion: cancelDeletion ??
                    (uid) async {
                      cancelled.add(uid);
                      await firestore.doc('deletionRequests/$uid').delete();
                    },
              );
            },
          ),
        ),
      );

  Future<SyncTrigger> signIn(
    WidgetTester tester, {
    required Future<DeletionRequest?> Function(String uid) pendingDeletion,
    Future<void> Function(String uid)? cancelDeletion,
    Key? gateKey,
  }) async {
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(
      trigger,
      pendingDeletion: pendingDeletion,
      cancelDeletion: cancelDeletion,
      gateKey: gateKey,
    ));
    auth.emit(const AppUser(uid: 'uid-1', email: 'a@b.com'));
    await tester.pumpAndSettle();
    return trigger;
  }

  final notice = find.byKey(const Key('gate.deletionPending'));

  testWidgets(
      'a returning user inside the grace window is told BEFORE onboarding, '
      'not after it and not only in Settings', (tester) async {
    // The state a deletion request leaves behind: everything wiped, including
    // `onboardingComplete`.
    await signIn(tester, pendingDeletion: (_) async => pendingRequest);

    expect(notice, findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('it says what is pending, when, and that cancelling restores',
      (tester) async {
    await signIn(tester, pendingDeletion: (_) async => pendingRequest);

    expect(find.textContaining('scheduled to be permanently deleted'),
        findsOneWidget);
    // The date the user was promised, formatted, not a vague "soon".
    expect(find.textContaining('August 31, 2026'), findsOneWidget);
    expect(find.textContaining('nothing is deleted'), findsOneWidget);
    expect(find.byKey(const Key('gate.cancelDeletion')), findsOneWidget);
  });

  testWidgets('a marker with no readable deadline still warns, using the window',
      (tester) async {
    await signIn(
      tester,
      pendingDeletion: (_) async => const DeletionRequest(),
    );

    expect(notice, findsOneWidget);
    expect(
      find.textContaining(
        'within ${AccountDeletionService.graceWindow.inDays} days',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no request on record: the app renders normally, no notice',
      (tester) async {
    await signIn(tester, pendingDeletion: (_) async => null);

    expect(notice, findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets(
      'a failing marker read fails toward SHOWING the app -- this check must '
      'never lock anyone out of their own tracker', (tester) async {
    await signIn(
      tester,
      pendingDeletion: (_) async => throw Exception('permission-denied'),
    );

    expect(notice, findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets(
      'the check never blocks a build: with the read still in flight the app '
      'is already usable', (tester) async {
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(
      trigger,
      // Never completes — the worst case for a blocking implementation.
      pendingDeletion: (_) => Completer<DeletionRequest?>().future,
    ));
    auth.emit(const AppUser(uid: 'uid-1', email: 'a@b.com'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // And it gives up rather than hanging forever: let the timeout fire (which
    // also stops the pending timer outliving the test).
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets(
      'cancelling from the notice withdraws the request AND pulls the data '
      'back -- resume() alone is a no-op in a fresh session', (tester) async {
    await firestore.doc('deletionRequests/uid-1').set({'uid': 'uid-1'});
    await firestore
        .collection('users/uid-1/dailyLogs')
        .doc('2026-01-01')
        .set({'date': '2026-01-01', 'flow': 3, 'updatedAt': 1767225600000});

    await signIn(tester, pendingDeletion: (_) async => pendingRequest);
    expect(await DailyLogRepository(db).getAll(), isEmpty,
        reason: 'precondition: the requesting device was wiped');

    await tester.tap(find.byKey(const Key('gate.cancelDeletion')));
    await tester.pumpAndSettle();

    expect(cancelled, ['uid-1']);
    expect(notice, findsNothing);
    // The point of MINOR-5: without an explicit sync the user sits on a wiped
    // device until they background and foreground the app.
    expect(await DailyLogRepository(db).getAll(), hasLength(1));
  });

  testWidgets(
      'a FAILED cancel keeps the notice up and says so -- dismissing would '
      'tell the user the deletion is off while it is still scheduled',
      (tester) async {
    await signIn(
      tester,
      pendingDeletion: (_) async => pendingRequest,
      cancelDeletion: (_) async => throw Exception('offline'),
    );

    await tester.tap(find.byKey(const Key('gate.cancelDeletion')));
    await tester.pumpAndSettle();

    expect(notice, findsOneWidget);
    expect(find.byKey(const Key('gate.deletionCancelFailed')), findsOneWidget);
  });

  testWidgets('signing out from the notice never wipes local data',
      (tester) async {
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
    await signIn(tester, pendingDeletion: (_) async => pendingRequest);
    expect(notice, findsOneWidget);

    await tester.tap(find.byKey(const Key('gate.signOut')));
    await tester.pumpAndSettle();

    expect(auth.signOutCalled, isTrue);
    expect(await DailyLogRepository(db).getAll(), hasLength(1));
    expect(notice, findsNothing);
  });

  testWidgets(
      'the answer is per-account: signing out and in as someone else re-asks '
      'rather than latching the previous verdict', (tester) async {
    final asked = <String>[];
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(
      trigger,
      pendingDeletion: (uid) async {
        asked.add(uid);
        return uid == 'uid-1' ? pendingRequest : null;
      },
    ));
    auth.emit(const AppUser(uid: 'uid-1', email: 'a@b.com'));
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);

    auth.emit(null);
    await tester.pumpAndSettle();
    claimStore = const ClaimRecord(uid: 'uid-2', declined: false);
    auth.emit(const AppUser(uid: 'uid-2', email: 'b@b.com'));
    await tester.pumpAndSettle();

    expect(asked, ['uid-1', 'uid-2']);
    // uid-2 has no request; a latched verdict would have shown it the notice.
    expect(notice, findsNothing);
  });

  testWidgets(
      'app lock outranks the notice: on a SECOND device the PIN was never '
      'cleared, and the notice must not become a pre-lock way past it',
      (tester) async {
    // The second-device state. `deleteAllData()` ran on the OTHER device, so
    // here the PIN, the settings and the history are all still in place — and
    // the marker read still succeeds, because it is per-account.
    await SettingsRepository(db).update(const AppSettingsCompanion(
      appLockEnabled: Value(true),
      onboardingComplete: Value(true),
    ));

    await signIn(tester, pendingDeletion: (_) async => pendingRequest);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(notice, findsNothing);
    // Each of these is an action the holder of a locked phone must not have:
    // learning the account is scheduled for deletion, cancelling it (which
    // pulls the entire cloud history down onto the device), and signing out —
    // a pre-lock exit that leads to the claim sheet under another account.
    expect(find.textContaining('scheduled to be permanently deleted'),
        findsNothing);
    expect(find.byKey(const Key('gate.cancelDeletion')), findsNothing);
    expect(find.byKey(const Key('gate.signOut')), findsNothing);
  });

  testWidgets(
      'the notice is dismissible: a pending request must not lock the user out '
      'of their own LOCAL tracker for the whole grace window', (tester) async {
    await signIn(
      tester,
      pendingDeletion: (_) async => pendingRequest,
      gateKey: const ValueKey('launch-1'),
    );
    expect(notice, findsOneWidget);

    await tester.tap(find.byKey(const Key('gate.dismissDeletionNotice')));
    await tester.pumpAndSettle();

    // Past the notice and into the app, WITHOUT cancelling the deletion and
    // without signing out — the two exits the screen used to offer.
    expect(notice, findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(cancelled, isEmpty);
    expect(auth.signOutCalled, isFalse);

    // Session-only: a fresh gate (a relaunch) re-reads the marker and warns
    // again, so dismissing is not a durable "don't tell me".
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(
      trigger,
      pendingDeletion: (_) async => pendingRequest,
      gateKey: const ValueKey('launch-2'),
    ));
    await tester.pumpAndSettle();

    expect(notice, findsOneWidget);
  });
}
