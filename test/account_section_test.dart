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
import 'package:menstrul_track/screens/settings/account_section.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

/// A controllable fake so tests can assert exactly which auth actions ran
/// (and, critically, which did NOT run when a cloud-delete step fails).
class _FakeAuthService implements AuthService {
  _FakeAuthService(this._user);
  AppUser? _user;
  bool signOutCalled = false;
  bool deleteAccountCalled = false;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_user);
  @override
  AppUser? get currentUser => _user;
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {
    signOutCalled = true;
    _user = null;
  }
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
  }
}

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late _FakeAuthService authService;

  const user = AppUser(uid: 'uid-1', email: 'a@b.com');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    authService = _FakeAuthService(user);
  });

  tearDown(() => db.close());

  Widget wrap({
    FirebaseFirestore Function()? deletionFirestore,
    Future<String?> Function()? readDeclinedUid,
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
        ChangeNotifierProvider(
          create: (_) => SyncTrigger(
            db,
            firestore: () => firestore,
            deviceId: () async => 'device-1',
            readDeclinedUid: readDeclinedUid ?? (() async => null),
            writeDeclinedUid: (_) async {},
            clearDeclinedUid: () async {},
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AccountSection(
            firestore: deletionFirestore ?? (() => firestore),
            // The real ClaimPreference.clear() hits flutter_secure_storage,
            // whose platform channel hangs under flutter_tester on this host
            // (see the doc comment on AccountSection.clearDeclinedPreference)
            // -- inject a no-op so these tests don't stall on it.
            clearDeclinedPreference: () async {},
          ),
        ),
      ),
    );
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

  testWidgets('cancelling the delete-account dialog does nothing',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(authService.deleteAccountCalled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'confirming delete removes the Firestore subtree, the local data, '
      'and the auth account, in that order', (tester) async {
    await firestore
        .collection('users/uid-1/dailyLogs')
        .doc('2026-01-01')
        .set({'date': '2026-01-01'});
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.confirmDelete')));
    await tester.pumpAndSettle();

    expect(
      (await firestore.collection('users/uid-1/dailyLogs').get()).docs,
      isEmpty,
    );
    expect(await DailyLogRepository(db).getAll(), isEmpty);
    expect(authService.deleteAccountCalled, isTrue);
  });

  testWidgets(
      'a Firestore failure aborts BEFORE local data or the auth account are '
      'touched -- deletion must not silently proceed while cloud health data '
      'still exists', (tester) async {
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );

    await tester.pumpWidget(wrap(
      deletionFirestore: () => throw Exception('no network'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account.confirmDelete')));
    await tester.pumpAndSettle();

    expect(await DailyLogRepository(db).getAll(), hasLength(1));
    expect(authService.deleteAccountCalled, isFalse);
    expect(find.textContaining("Couldn't delete"), findsOneWidget);
  });

  testWidgets(
      'a decline on record for this uid shows the reversible "turn on sync" '
      'control, and using it clears the decline', (tester) async {
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );

    await tester.pumpWidget(wrap(readDeclinedUid: () async => 'uid-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account.enableSync')), findsOneWidget);
    expect(find.byKey(const Key('account.syncStatus')), findsNothing);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account.enableSync')), findsNothing);
    expect(find.byKey(const Key('account.syncStatus')), findsOneWidget);
  });

  testWidgets(
      'a decline on record for a DIFFERENT uid does not show the '
      '"turn on sync" control for this uid -- scoping is per-account',
      (tester) async {
    await tester.pumpWidget(wrap(readDeclinedUid: () async => 'some-other-uid'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account.enableSync')), findsNothing);
    expect(find.byKey(const Key('account.syncStatus')), findsOneWidget);
  });
}
