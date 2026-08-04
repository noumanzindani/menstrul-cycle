import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../providers/auth_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/account_deletion_service.dart';
import '../../services/claim_preference.dart';
import '../../services/firestore_ref.dart';
import '../../services/sync_trigger.dart';

/// Signed-in identity, cloud-sync status (reversible if the user declined to
/// upload their pre-existing local data at sign-in — see
/// `claim_local_data_sheet.dart` / `SyncTrigger.resolveClaim`), sign-out, and
/// full account deletion.
class AccountSection extends StatefulWidget {
  const AccountSection({
    super.key,
    FirebaseFirestore Function()? firestore,
    Future<void> Function()? clearDeclinedPreference,
  })  : firestore = firestore ?? lunaFirestore,
        clearDeclinedPreference =
            clearDeclinedPreference ?? ClaimPreference.clear;

  /// Overridable so tests can inject a fake Firestore instead of touching the
  /// real `Firebase.app()` singleton — mirrors `SyncTrigger`'s identical seam
  /// (see its doc comment) for the same reason: `lunaFirestore()` throws with
  /// no Firebase app configured, which is the current state of this app
  /// (Firebase console setup is a separate, still-pending task).
  final FirebaseFirestore Function() firestore;

  /// Overridable for the same reason `SyncTrigger`'s decline hooks are:
  /// `ClaimPreference`'s default is backed by `flutter_secure_storage`, whose
  /// platform channel has no handler in `flutter_tester` on this host and
  /// hangs indefinitely rather than throwing — confirmed directly while
  /// building this widget. `pumpAndSettle` does not wait on a stuck platform
  /// channel call (it only waits on scheduled frames), so an uninjected call
  /// here does not time the test out; it silently leaves the awaited
  /// deletion pipeline stalled before `auth.deleteAccount()` ever runs,
  /// which is a much easier bug to miss than an outright hang.
  final Future<void> Function() clearDeclinedPreference;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// Whether the currently signed-in uid has an on-record decline from the
  /// claim-local-data prompt. `SyncTrigger.isPendingClaim` is deliberately a
  /// plain, non-reactive getter (its own doc comment explains why
  /// `notifyListeners()` isn't an option: it broke `widget_test.dart` with a
  /// setState-during-build error). Rather than re-litigating that, this
  /// widget owns a small piece of its own state instead: a cached Future
  /// keyed by uid, invalidated whenever the signed-in uid changes and
  /// refreshed manually right after [_enableSync] flips it. This performs its
  /// own read via `SyncTrigger.declinedUidOnRecord()` (already the accessor
  /// `AppGate` uses), so it needs no new API on `SyncTrigger` itself.
  Future<bool>? _declinedFuture;
  String? _declinedFutureUid;

  Future<bool> _checkDeclined(SyncTrigger trigger, String uid) async {
    return await trigger.declinedUidOnRecord() == uid;
  }

  void _ensureDeclinedFuture(SyncTrigger trigger, String? uid) {
    if (uid == null) {
      _declinedFuture = null;
      _declinedFutureUid = null;
      return;
    }
    if (_declinedFutureUid != uid) {
      _declinedFutureUid = uid;
      _declinedFuture = _checkDeclined(trigger, uid);
    }
  }

  /// Reverses an earlier "keep on this device only" decision. This is the
  /// control the task-11 addendum requires: the decline persisted by
  /// `SyncTrigger.resolveClaim(upload: false)` must be reversible, and this is
  /// the only place in the app that calls `resolveClaim(upload: true)` outside
  /// the claim sheet itself (which a decline, by definition, suppresses from
  /// ever showing again) — without this, a decline is permanent.
  Future<void> _enableSync(String uid) async {
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    await trigger.resolveClaim(upload: true);
    await settings.load(); // pick up the fresh lastSyncedAt after syncing
    if (!mounted) return;
    setState(() {
      _declinedFutureUid = uid;
      _declinedFuture = Future.value(false);
    });
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and every log stored in the '
          'cloud. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('account.confirmDelete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Only what the (possibly-aborting) Firestore step itself needs is
    // captured up front. `LogProvider`/`MedicationProvider`/`SettingsProvider`
    // are read further down, AFTER that step succeeds — reading them here
    // unconditionally would make even the abort path (Firestore failure)
    // depend on providers it never touches.
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);

    // Firestore data FIRST: deleting the auth user first would leave the
    // subtree orphaned with no identity able to reach it. If THIS step
    // fails, stop right here — proceeding to wipe local data or the auth
    // account while cloud health data still exists would tell the user
    // deletion succeeded while their data is still sitting in Firestore,
    // exactly the failure this feature exists to prevent.
    try {
      await AccountDeletionService(firestore: widget.firestore(), uid: uid)
          .deleteFirestoreData();
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          "Couldn't delete your cloud data. Check your connection and try "
          'again.',
        ),
      ));
      return;
    }
    if (!context.mounted) return;
    final logs = context.read<LogProvider>();
    final meds = context.read<MedicationProvider>();
    final settings = context.read<SettingsProvider>();

    // Then the local mirror. Without this the logs stay on the device, and
    // the claim-local-data prompt would offer to upload the "deleted" data
    // into the next account created here.
    await db.deleteAllData();
    // `LogProvider`/`SettingsProvider`/`MedicationProvider` cache what they
    // last loaded in memory and are NOT auto-refreshed by a direct DB write —
    // `deleteAllData()` already wiped the rows underneath them. Without this,
    // this device's cached (pre-deletion) data would still render if another
    // account signs in afterward on the same device, since this app has one
    // shared local database regardless of who is currently signed in.
    // Mirrors the identical reload the in-app "delete all my data" control
    // already does (`settings_screen.dart._confirmDeleteAll`).
    await settings.load();
    await logs.load();
    await meds.load();
    // The decline record is uid-scoped and this uid no longer exists —
    // leaving it on disk is stale state serving no purpose (task-11 addendum
    // §4).
    await widget.clearDeclinedPreference();
    await auth.deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final trigger = context.read<SyncTrigger>();
    final settings = context.watch<SettingsProvider>();
    final uid = auth.user?.uid;
    _ensureDeclinedFuture(trigger, uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Account'),
          subtitle: Text(auth.user?.email ?? 'Not signed in'),
        ),
        if (uid != null)
          FutureBuilder<bool>(
            future: _declinedFuture,
            builder: (context, snapshot) {
              final declined = snapshot.data ?? false;
              if (declined) {
                return ListTile(
                  key: const Key('account.enableSync'),
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Cloud sync is off'),
                  subtitle: const Text(
                    'Your logs stay on this device only. You can turn sync '
                    'on any time.',
                  ),
                  trailing: TextButton(
                    onPressed: () => _enableSync(uid),
                    child: const Text('Turn on'),
                  ),
                );
              }
              return ListTile(
                key: const Key('account.syncStatus'),
                leading: const Icon(Icons.cloud_done_outlined),
                title: const Text('Cloud sync is on'),
                subtitle: Text(
                  settings.lastSyncedAt != null
                      ? 'Your logs are backed up and synced across devices.'
                      : 'Not synced yet — this happens automatically.',
                ),
              );
            },
          ),
        ListTile(
          key: const Key('account.signOut'),
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle: const Text('Your logs stay on this device'),
          onTap: () => context.read<AuthProvider>().signOut(),
        ),
        ListTile(
          key: const Key('account.delete'),
          leading: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Delete account'),
          subtitle: const Text('Permanently removes your cloud data'),
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }
}
