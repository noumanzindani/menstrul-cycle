import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/screens/onboarding/onboarding_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// Restoring the signup baseline before the wizard is ever shown.
///
/// `onboardingComplete` is deliberately device-local, so a reinstall re-asks all
/// eleven signup pages. Answering them stamps `settingsUpdatedAt` with NOW,
/// which beats the cloud copy under last-writer-wins, and the next
/// `_pushSettings` blind-`set()`s the fresh answers over the stored ones. The
/// recovery attempt destroys the backup. Reading FIRST is what breaks that
/// chain, and the last test here proves the chain stays broken.
class _SignedInAuth implements AuthService {
  static const _user = AppUser(uid: 'uid-1', email: 'a@b.c');

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

/// A trigger whose restore answer the test writes.
///
/// Subclassed rather than injected through `AppGate`: the gate reads the
/// [SyncTrigger] already in the tree, so overriding the one method under test
/// exercises the real production path instead of a parallel one.
class _ScriptedTrigger extends SyncTrigger {
  _ScriptedTrigger(
    super.db, {
    required this.script,
    required super.firestore,
    required super.deviceId,
    required super.readClaim,
    required super.writeClaim,
  });

  final Future<bool> Function() script;

  @override
  Future<bool> restoreSettingsForFirstRun() => script();
}

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  ClaimRecord? claimStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    // Recorded, so the claim sheet does not sit in front of what is under test.
    claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
  });

  tearDown(() => db.close());

  SyncTrigger buildTrigger({Future<bool> Function()? script}) => script == null
      ? SyncTrigger(
          db,
          firestore: () => firestore,
          deviceId: () async => 'device-1',
          readClaim: () async => claimStore,
          writeClaim: (r) async => claimStore = r,
        )
      : _ScriptedTrigger(
          db,
          script: script,
          firestore: () => firestore,
          deviceId: () async => 'device-1',
          readClaim: () async => claimStore,
          writeClaim: (r) async => claimStore = r,
        );

  /// Advances a fixed number of frames instead of waiting for quiescence.
  ///
  /// Settling cannot be used here: the gate's splash carries an INDETERMINATE
  /// `LinearProgressIndicator`, which animates forever, so "settled" is a state
  /// this tree never reaches while a restore is in flight. That is a property of
  /// the screen, not a fault to fix.
  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<SyncTrigger> pumpApp(
    WidgetTester tester, {
    Future<bool> Function()? script,
  }) async {
    // No `addTearDown(trigger.dispose)`: `LunarFlowApp`'s ChangeNotifierProvider
    // uses `create:`, so the tree owns this object and disposes it itself. A
    // second dispose here throws "used after being disposed".
    final trigger = buildTrigger(script: script);
    await tester.pumpWidget(LunarFlowApp(
      database: db,
      authService: _SignedInAuth(),
      syncTrigger: trigger,
    ));
    await frames(tester);
    return trigger;
  }

  Future<void> writeRemote(Map<String, dynamic> data) =>
      firestore.doc('users/uid-1/settings/current').set(data);

  Map<String, dynamic> baselineDoc({int cycleLength = 30, int? updatedAt}) => {
        'dateOfBirth': DateTime(2002, 9, 10).millisecondsSinceEpoch,
        'defaultCycleLength': cycleLength,
        'profileFields': 3,
        'updatedAt': updatedAt ?? DateTime(2026, 9, 1).millisecondsSinceEpoch,
      };

  testWidgets('an account that already answered signup skips the wizard',
      (tester) async {
    await writeRemote(baselineDoc());
    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsNothing,
        reason: 'the user was re-asked eleven pages of questions they had '
            'already answered');
    final row = await db.getSettings();
    expect(row.onboardingComplete, isTrue);
    expect(row.defaultCycleLength, 30, reason: 'the baseline did not land');
  });

  testWidgets('an account with no stored document still gets the wizard',
      (tester) async {
    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect((await db.getSettings()).onboardingComplete, isFalse);
  });

  testWidgets('a preferences-only document is NOT a completed signup',
      (tester) async {
    // Theme and language are written by a user who never finished the wizard.
    // Treating that as "already onboarded" would skip signup for an account
    // with no profile at all, stranding them with no route back.
    await writeRemote({
      'themeMode': 'dark',
      'language': 'en',
      'updatedAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
    });
    await pumpApp(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('a restore that throws falls back to the wizard', (tester) async {
    // Fails toward asking. Re-asking is recoverable; skipping the wizard for an
    // account that never answered is not.
    await pumpApp(tester, script: () async => throw StateError('offline'));

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('while the read is in flight, the wizard is NOT rendered',
      (tester) async {
    // The same mistake the diary made: a confident answer given before it is
    // known. Rendering the wizard here starts someone on page one while the
    // answers they already gave are on their way down.
    final gate = Completer<bool>();
    await pumpApp(tester, script: () => gate.future);

    expect(find.byType(OnboardingScreen), findsNothing,
        reason: 'the wizard flashed before the restore had answered');
    expect(find.byKey(const Key('appGate.splash')), findsOneWidget);

    gate.complete(false);
    await frames(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget,
        reason: 'the gate never resolved once the restore answered');
  });

  testWidgets('THE REGRESSION: a restored baseline is not pushed back over '
      'the stored one', (tester) async {
    // `_pullSettings` stamps the local row with the REMOTE `settingsUpdatedAt`
    // rather than now, so the two sides tie and `_pushSettings` declines. If
    // that ever changes, the restore starts overwriting the very document it
    // just read -- the original bug wearing a different hat.
    const remoteMillis = 1756684800000; // 2026-09-01T00:00:00Z
    await writeRemote(baselineDoc(updatedAt: remoteMillis));

    final trigger = await pumpApp(tester);
    await trigger.syncNow();
    await frames(tester);

    final after =
        (await firestore.doc('users/uid-1/settings/current').get()).data()!;
    expect(after['defaultCycleLength'], 30,
        reason: 'the device pushed its local defaults back over the stored '
            'baseline it had just restored');
    expect(after['updatedAt'], remoteMillis,
        reason: 'the stored document was rewritten by the device that just '
            'read it');
  });
}
