import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository logs;
  late FakeFirebaseFirestore firestore;

  /// Stands in for `ClaimPreference`'s persisted storage across the whole
  /// test (not reset per `trigger()` call), so a NEW `SyncTrigger` instance
  /// reading from it simulates a decision surviving an app relaunch.
  ClaimRecord? claimStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = DailyLogRepository(db);
    firestore = FakeFirebaseFirestore();
    claimStore = null;
  });

  tearDown(() => db.close());

  SyncTrigger trigger([AppDatabase? database]) => SyncTrigger(
        database ?? db,
        firestore: () => firestore,
        deviceId: () async => 'device-1',
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

  Future<Map<String, dynamic>?> remoteDay(
    DateTime date, {
    String uid = 'uid-1',
  }) async {
    final id =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final doc =
        await firestore.collection('users/$uid/dailyLogs').doc(id).get();
    return doc.data();
  }

  Future<void> seedLog(DateTime date) => logs.upsert(
        date: date,
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

  /// Pretends some earlier sync already ran on this device. `lastSyncedAt` is
  /// device-global — it says nothing about WHICH account synced — which is
  /// precisely why the claim gate must not key on it.
  Future<void> markDeviceSyncedAt(DateTime when) async {
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0)))
        .write(AppSettingsCompanion(lastSyncedAt: Value(when)));
  }

  group('unclaimed local data (fresh account/device pairing)', () {
    test('setUser does NOT push pre-existing local logs before consent',
        () async {
      await seedLog(DateTime(2026, 1, 5));

      await trigger().setUser('uid-1');

      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test('resolveClaim(upload: true) pushes the deferred local logs',
        () async {
      await seedLog(DateTime(2026, 1, 5));

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: true);

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
    });

    test(
        'resolveClaim(upload: false) leaves the data unpushed even after a '
        'later syncNow (e.g. an app resume or a new edit)', () async {
      await seedLog(DateTime(2026, 1, 5));

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: false);
      // Simulate the app-resume hook and/or a debounced write firing later
      // in the same session.
      await t.syncNow();
      await t.syncNow();

      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test(
        'the gate is closed from setUser\'s first synchronous instant: a '
        'syncNow racing a slow first database read pushes nothing', () async {
      // In production the database opens through a `LazyDatabase` (documents
      // dir + keystore read + sqlite open), so the FIRST query after sign-in
      // takes hundreds of milliseconds — and Android delivers `resumed`, which
      // calls `AppGate`'s syncNow hook, shortly after startup. An in-memory DB
      // hides that window entirely (it is microtask-only and unhittable), so
      // this test reproduces it: a file-backed database opened lazily behind a
      // 300ms delay, with the resume hook firing 50ms in.
      final dir = await Directory.systemTemp.createTemp('luna_claim_race');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/luna.db');

      final seed = AppDatabase.forTesting(NativeDatabase(file));
      await DailyLogRepository(seed).upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );
      await seed.close();

      final slow = AppDatabase.forTesting(LazyDatabase(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return NativeDatabase(file);
      }));
      addTearDown(slow.close);

      final t = trigger(slow);
      final signIn = t.setUser('uid-1'); // deliberately not awaited
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.syncNow(); // AppGate.didChangeAppLifecycleState -> resumed
      await signIn;

      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test(
        'a setUser continuation that resumes AFTER the account changed cannot '
        'reopen the gate or push into the account it was started for',
        () async {
      // `setUser` mutates `_uid`, `_service` and `_pendingClaim` across awaits.
      // Setting the gate synchronously closes the race against an interleaving
      // CALLER, but an older invocation of setUser itself can still resume and
      // undo it. In production the blocking await is `DeviceId.get()` --
      // flutter_secure_storage, i.e. the OS keystore -- which is exactly the
      // kind of call that can take hundreds of milliseconds on a cold start,
      // and a sign-out/sign-in is reachable from Settings at any moment.
      final firstDeviceIdCall = Completer<void>();
      var deviceIdCalls = 0;

      // uid-2 has already claimed this device, so ITS continuation would
      // happily clear the gate and sync.
      claimStore = const ClaimRecord(uid: 'uid-2', declined: false);
      await seedLog(DateTime(2026, 1, 5));

      final t = SyncTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async {
          deviceIdCalls++;
          if (deviceIdCalls == 1) await firstDeviceIdCall.future;
          return 'device-1';
        },
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

      final stale = t.setUser('uid-2'); // blocks inside the device-id read
      await Future<void>.delayed(Duration.zero);
      final current = t.setUser('uid-1'); // the account actually signed in now
      await current;
      expect(t.isPendingClaim, isTrue, reason: 'uid-1 has never been asked');

      firstDeviceIdCall.complete(); // uid-2's continuation resumes
      await stale;

      expect(t.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5), uid: 'uid-1'), isNull);
      expect(await remoteDay(DateTime(2026, 1, 5), uid: 'uid-2'), isNull);
    });

    test(
        'health SETTINGS with no logged days are gated too -- dailyLogs is not '
        'the only collection a first sync pushes', () async {
      // Reachable: a local-only user in pregnancy mode who has not logged
      // days. `SyncService._pushSettings` uploads `users/{uid}/settings/current`
      // including `pregnancyStartDate`, so keying the gate on dailyLogs alone
      // pushed the most sensitive field in the app with no prompt at all -- and
      // recorded an `uploaded` consent the user never gave.
      await SettingsRepository(db).update(
        AppSettingsCompanion(pregnancyStartDate: Value(DateTime(2026, 1, 1))),
      );

      final t = trigger();
      await t.setUser('uid-1');
      await t.syncNow(); // the app-resume hook

      expect(t.isPendingClaim, isTrue);
      expect(claimStore, isNull, reason: 'no consent was given to record');
      expect(
        (await firestore.doc('users/uid-1/settings/current').get()).exists,
        isFalse,
      );
    });

    test('resolveClaim(upload: true) pushes the deferred health settings',
        () async {
      await SettingsRepository(db).update(
        AppSettingsCompanion(pregnancyStartDate: Value(DateTime(2026, 1, 1))),
      );

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: true);

      expect(
        (await firestore.doc('users/uid-1/settings/current').get()).exists,
        isTrue,
      );
    });

    test('a pending deletion tombstone is local data worth claiming too',
        () async {
      // `_pushTombstones` publishes one marker per deleted date into
      // `users/{uid}/deletions`; a date this person tracked and then removed is
      // still a statement about their cycle.
      await seedLog(DateTime(2026, 1, 5));
      await logs.deleteForDate(DateTime(2026, 1, 5));
      expect(await logs.getAll(), isEmpty);

      final t = trigger();
      expect(await t.hasLocalDataToClaim(), isTrue);

      await t.setUser('uid-1');

      expect(t.isPendingClaim, isTrue);
      expect(claimStore, isNull);
    });
  });

  group('persisting the decision, scoped to the account that made it', () {
    test('resolveClaim(upload: false) records the decline for that uid',
        () async {
      await seedLog(DateTime(2026, 1, 5));

      final t = trigger();
      await t.setUser('uid-1');
      expect(await t.declinedUidOnRecord(), isNull);

      await t.resolveClaim(upload: false);

      expect(await t.declinedUidOnRecord(), 'uid-1');
    });

    test(
        'a decline survives a fresh SyncTrigger instance (an app relaunch) '
        '-- syncNow stays a no-op and no local logs are pushed', () async {
      await seedLog(DateTime(2026, 1, 5));

      final first = trigger();
      await first.setUser('uid-1');
      await first.resolveClaim(upload: false);

      // A brand-new SyncTrigger, as `main.dart` constructs at every app
      // launch, backed by the SAME persisted store.
      final relaunch = trigger();
      await relaunch.setUser('uid-1');
      await relaunch.syncNow(); // e.g. the app-resume hook firing

      expect(relaunch.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test(
        'a decline recorded for uid-1 does NOT suppress the question for a '
        'DIFFERENT uid-2 -- that account has never been asked', () async {
      await seedLog(DateTime(2026, 1, 5));

      final first = trigger();
      await first.setUser('uid-1');
      await first.resolveClaim(upload: false);

      final second = trigger();
      await second.setUser('uid-2');

      // The record on file is still uid-1's -- the caller (AppGate) is the
      // one that compares it against the signed-in uid to decide whether to
      // re-prompt; this proves the record itself doesn't silently widen to
      // cover uid-2.
      expect((await second.claimOnRecord())?.uid, 'uid-1');
      expect(second.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5), uid: 'uid-2'), isNull);
    });

    test(
        'opting in later (resolveClaim(upload: true)) clears the earlier '
        'decline and runs the deferred sync', () async {
      await seedLog(DateTime(2026, 1, 5));

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: false);
      expect(await t.declinedUidOnRecord(), 'uid-1');

      await t.resolveClaim(upload: true);

      expect(await t.declinedUidOnRecord(), isNull);
      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
    });

    test('a declined account stays gated even with no local logs at all',
        () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: true);

      final t = trigger();
      await t.setUser('uid-1');

      expect(t.isPendingClaim, isTrue);
    });
  });

  group('a second account signing in on the same device', () {
    test(
        'is gated even though this DEVICE has synced before -- lastSyncedAt '
        'is device-global and must not answer for a new account', () async {
      // The device-global marker some earlier account left behind.
      await markDeviceSyncedAt(DateTime(2026, 1, 1));
      // A local row written well after it, so the push filter
      // (`updatedAt.isBefore(since)`) cannot be what holds it back.
      await seedLog(DateTime(2026, 3, 5));

      final t = trigger();
      await t.setUser('uid-2');
      await t.syncNow(); // the app-resume hook

      expect(t.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 3, 5), uid: 'uid-2'), isNull);
    });

    test(
        'does not inherit the first account\'s consent: uid-1 uploads, then '
        'uid-2 signs in and nothing of uid-1\'s device reaches users/uid-2',
        () async {
      await seedLog(DateTime(2026, 1, 5));
      final first = trigger();
      await first.setUser('uid-1');
      await first.resolveClaim(upload: true);
      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
      // More logging after that first sync, so these rows are unambiguously
      // inside any later push window.
      await seedLog(DateTime(2026, 3, 5));

      // Sign out, sign in as someone else (Settings ships a sign-out button).
      final second = trigger();
      await second.setUser('uid-2');
      await second.syncNow();

      expect(second.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5), uid: 'uid-2'), isNull);
      expect(await remoteDay(DateTime(2026, 3, 5), uid: 'uid-2'), isNull);
    });

    test('is re-gated within the SAME SyncTrigger instance on a uid change',
        () async {
      await seedLog(DateTime(2026, 1, 5));

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: true);
      expect(t.isPendingClaim, isFalse);

      await t.setUser('uid-2'); // no app restart in between

      expect(t.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5), uid: 'uid-2'), isNull);
    });
  });

  group('no unclaimed data — sync proceeds automatically', () {
    test('a fresh device with no local logs syncs (pulls remote data) right '
        'away, with no claim prompt needed', () async {
      await firestore.collection('users/uid-1/dailyLogs').doc('2026-01-05').set({
        'date': '2026-01-05',
        'flow': FlowIntensity.medium.index,
        'symptoms': <String, dynamic>{},
        'updatedAt': DateTime(2026, 1, 5).millisecondsSinceEpoch,
      });

      final t = trigger();
      await t.setUser('uid-1');

      final local = await logs.getForDate(DateTime(2026, 1, 5));
      expect(local, isNotNull);
      expect(t.isPendingClaim, isFalse);
      // The pairing is recorded, so signing out and back in later -- with rows
      // now on the device -- does not ask this account to "claim" its own
      // synced data.
      expect(claimStore, const ClaimRecord(uid: 'uid-1', declined: false));
    });

    test('an account that already claimed this device proceeds automatically '
        'even with local rows present', () async {
      await seedLog(DateTime(2026, 1, 5));
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);

      await trigger().setUser('uid-1');

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
    });
  });

  group('suspending sync for an account deletion', () {
    test(
        'suspend() stops everything: a re-armed debounce and a later syncNow '
        'cannot push into the account being deleted', () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      await seedLog(DateTime(2026, 1, 5));
      final t = trigger();
      await t.setUser('uid-1');
      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull); // syncing

      await t.suspend();

      // The deletion path itself re-arms sync: it reloads `LogProvider` after
      // wiping local data, and `main.dart`'s write-sync provider turns that
      // into a scheduleSync(). Neither that nor the app-resume hook may write
      // anything into a subtree that is being swept.
      await seedLog(DateTime(2026, 3, 5));
      t.scheduleSync();
      await t.syncNow();

      expect(await remoteDay(DateTime(2026, 3, 5)), isNull);
    });

    test('suspend() does not return while a sync is still in flight',
        () async {
      // A sweep that starts while a push is mid-flight loses the race: the
      // document lands after the sweep passes that collection and survives
      // the deletion. suspend() must therefore WAIT, not just set a flag.
      final dir = await Directory.systemTemp.createTemp('luna_suspend');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/luna.db');

      final seed = AppDatabase.forTesting(NativeDatabase(file));
      await DailyLogRepository(seed).upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );
      await seed.close();

      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final slow = AppDatabase.forTesting(LazyDatabase(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return NativeDatabase(file);
      }));
      addTearDown(slow.close);

      final t = trigger(slow);
      final signIn = t.setUser('uid-1'); // syncs; its first query blocks
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await t.suspend();

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
      await signIn;
    });

    test(
        'suspend() waits for the run that is actually WRITING, even when a '
        'second syncNow has landed on top of it', () async {
      // `SyncService.syncNow()` silently drops an overlapping call (its own
      // `_running` guard) and returns an already-complete future. Tracking only
      // the MOST RECENT call therefore replaced the real run's future with that
      // no-op, whose completion then cleared it -- so suspend() awaited nothing
      // and returned while a push was still on the wire, straight into the
      // deletion sweep. Both overlapping callers are routine: AppGate's
      // unawaited `resumed` hook and the 2-second scheduleSync debounce.
      final dir = await Directory.systemTemp.createTemp('luna_suspend_overlap');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/luna.db');

      final seed = AppDatabase.forTesting(NativeDatabase(file));
      await DailyLogRepository(seed).upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );
      await seed.close();

      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final slow = AppDatabase.forTesting(LazyDatabase(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return NativeDatabase(file);
      }));
      addTearDown(slow.close);

      final t = trigger(slow);
      final signIn = t.setUser('uid-1'); // syncs; its first query blocks
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The app comes back to the foreground, and a local edit's debounce
      // fires, while that first push is still mid-run.
      unawaited(t.syncNow());
      unawaited(t.syncNow());

      await t.suspend();

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
      await signIn;
    });

    test('resume() restores sync for the same account (an aborted deletion)',
        () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final t = trigger();
      await t.setUser('uid-1');
      await t.suspend();
      await seedLog(DateTime(2026, 3, 5));

      await t.resume();
      await t.syncNow();

      expect(await remoteDay(DateTime(2026, 3, 5)), isNotNull);
    });

    test('resume() re-evaluates the claim gate rather than assuming consent',
        () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: true);
      await seedLog(DateTime(2026, 1, 5));
      final t = trigger();
      await t.setUser('uid-1');
      await t.suspend();

      await t.resume();
      await t.syncNow();

      expect(t.isPendingClaim, isTrue);
      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test('a different account signing in lifts the suspend', () async {
      claimStore = const ClaimRecord(uid: 'uid-2', declined: false);
      final t = trigger();
      await t.setUser('uid-1');
      await t.suspend();

      await t.setUser('uid-2');
      await seedLog(DateTime(2026, 3, 5));
      await t.syncNow();

      expect(await remoteDay(DateTime(2026, 3, 5), uid: 'uid-2'), isNotNull);
    });
  });

  group('the sync-status signal a Settings surface can honestly read', () {
    test('is true only for the account that claimed this device', () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final t = trigger();
      await t.setUser('uid-1');

      expect(await t.isSyncEnabledFor('uid-1'), isTrue);
      expect(await t.isSyncEnabledFor('uid-2'), isFalse);
    });

    test('is false for a declined account', () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: true);
      final t = trigger();
      await t.setUser('uid-1');

      expect(await t.isSyncEnabledFor('uid-1'), isFalse);
    });

    test('is false while the claim question is still unanswered -- unanswered '
        'is not the same as declined', () async {
      await seedLog(DateTime(2026, 1, 5));
      final t = trigger();
      await t.setUser('uid-1');

      expect(await t.isSyncEnabledFor('uid-1'), isFalse);
      expect(await t.declinedUidOnRecord(), isNull);
    });

    test(
        'is false on a build with no Firebase app, even after the user chose '
        '"Add to my account" and a claim was recorded', () async {
      // This is the CURRENT state of every build of this app: the Firebase
      // console setup (task 1b) has not landed, so `lunaFirestore()` throws,
      // `setUser` catches, and no SyncService is ever built. The user is still
      // prompted, still taps "Add to my account", and `resolveClaim` still
      // records `uploaded` -- but `syncNow()` has nothing to run. Reporting
      // "Cloud sync is on" there is a false privacy statement in the direction
      // that matters most: it tells someone their health data is backed up when
      // not one byte has left the device.
      await seedLog(DateTime(2026, 1, 5));
      final t = SyncTrigger(
        db,
        firestore: () => throw StateError('no Firebase app'),
        deviceId: () async => 'device-1',
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );
      await t.setUser('uid-1');

      await t.resolveClaim(upload: true);

      expect(claimStore, const ClaimRecord(uid: 'uid-1', declined: false));
      expect(await t.isSyncEnabledFor('uid-1'), isFalse);
    });

    test('is false while setUser is still evaluating the claim decision',
        () async {
      // Mid-`setUser`: the record already says "uploaded", but the gate is set
      // and `syncNow` is refusing to run, so nothing is syncing yet.
      final release = Completer<void>();
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final t = SyncTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async {
          await release.future;
          return 'device-1';
        },
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

      final signIn = t.setUser('uid-1');
      await Future<void>.delayed(Duration.zero);

      expect(await t.isSyncEnabledFor('uid-1'), isFalse);

      release.complete();
      await signIn;

      expect(await t.isSyncEnabledFor('uid-1'), isTrue);
    });

    test('is false while sync is suspended, even for the claiming account',
        () async {
      claimStore = const ClaimRecord(uid: 'uid-1', declined: false);
      final t = trigger();
      await t.setUser('uid-1');
      await t.suspend();

      expect(await t.isSyncEnabledFor('uid-1'), isFalse);
    });
  });

  test('setUser does not throw when Firebase has not been initialized',
      () async {
    // No Firebase app exists in this test binary (task 1b -- the console
    // setup -- is deliberately deferred). The DEFAULT constructor (no
    // overrides) touches the real `lunaFirestore()`, which throws in that
    // state; the trigger must swallow it and leave sync disabled rather than
    // crashing the app, since `LunaTrackApp.build` calls `setUser` on every
    // signed-in rebuild, including in widget tests that sign a fake user in
    // with no Firebase app configured at all. `lunaFirestore()` is evaluated
    // BEFORE `DeviceId.get()`/`ClaimPreference.read()`, so this also never
    // reaches flutter_secure_storage (whose channel hangs under
    // flutter_tester on this host).
    final t = SyncTrigger(db);
    await t.setUser('uid-1');
    await t.syncNow();
  });
}
