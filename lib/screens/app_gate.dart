import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily_log_repository.dart';
import '../db/database.dart';
import '../providers/auth_provider.dart';
import '../providers/log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/account_deletion_service.dart';
import '../services/claim_preference.dart';
import '../services/firebase_availability.dart';
import '../services/firestore_ref.dart';
import '../services/sync_trigger.dart';
import '../widgets/cloud_sync_unavailable_banner.dart';
import 'account/deletion_pending_screen.dart';
import 'app_shell.dart';
import 'auth/claim_local_data_sheet.dart';
import 'auth/sign_in_screen.dart';
import 'lock/app_lock.dart';
import 'onboarding/onboarding_screen.dart';

/// Decides which top-level surface the signed-in state calls for: splash,
/// sign-in, the deletion notice, onboarding, or the app itself.
///
/// It does NOT render the app lock. That is [AppLock], installed above the
/// Navigator by `MaterialApp.builder` so it covers every route rather than only
/// this one — see `screens/lock/app_lock.dart`. This gate only *consults* it,
/// through [AppLock.isLocked], to avoid raising a modal question at a moment the
/// user can neither see nor answer.
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    this.pendingDeletion = _livePendingDeletion,
    this.cancelDeletion = _liveCancelDeletion,
  });

  /// The deletion-request marker read, and its withdrawal.
  ///
  /// Injected for the reason `AccountSection`'s identical seam is: the live
  /// implementations go through `lunaFirestore()`, which throws with no
  /// initialized Firebase app — the state of every test harness, and of this
  /// build until the console setup lands.
  final Future<DeletionRequest?> Function(String uid) pendingDeletion;
  final Future<void> Function(String uid) cancelDeletion;

  static Future<DeletionRequest?> _livePendingDeletion(String uid) =>
      AccountDeletionService(firestore: lunaFirestore(), uid: uid)
          .pendingRequest();

  static Future<void> _liveCancelDeletion(String uid) =>
      AccountDeletionService(firestore: lunaFirestore(), uid: uid)
          .cancelDeletion();

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  /// The uid the claim prompt has already been raised for this session, NOT a
  /// bare "shown once" bool: a bool latched forever, so after uid-1 answered,
  /// uid-2 signing in on the same device (Settings now has a sign-out button)
  /// was never asked — and, because `SyncTrigger.setUser` leaves the gate set
  /// for an unanswered account, uid-2 then got no sync at all, silently.
  String? _claimPromptShownFor;

  /// The uid the deletion-marker read has already been issued for, and its
  /// result. Same per-uid keying as [_claimPromptShownFor], for the same
  /// reason: a bare bool would latch across a sign-out and sign-in.
  String? _deletionCheckedFor;
  DeletionRequest? _pendingDeletion;

  /// Whether this gate has ever rendered the app for an UNLOCKED session.
  ///
  /// It decides what sits under the lock, and both directions matter. Before
  /// the first unlock — a cold start behind the lock — there is nothing to
  /// preserve, so the gate renders a bare placeholder and the shell, its
  /// providers and its side effects are simply not started underneath a lock
  /// the user has never been past. After it, the tree is never torn down again:
  /// keeping it mounted (offstage, under [AppLock]) is exactly what puts the
  /// user back on the same screen, in the same open sheet, at the same scroll
  /// offset when they unlock. Rebuilding it would silently lose all of that.
  bool _appEverRendered = false;

  /// Whether the user has chosen "Continue without syncing" on the sign-in
  /// screen's cloud-outage hatch.
  ///
  /// The owner's ruling (2026-08-06): a missing/failed Firebase app must never
  /// lock someone out of their own local encrypted health data, so the
  /// sign-in wall offers this way past itself -- but ONLY then. It is offered
  /// by `SignInScreen` (see `showContinueWithoutSync` there) purely off
  /// [FirebaseAvailability], read fresh in [build] below, never off an
  /// [AuthErrorCode]: an error code cannot tell a genuine outage apart from a
  /// mistyped password, and gating on it would hand every user a local-only
  /// bypass of the required-account design the moment they fat-finger their
  /// credentials.
  ///
  /// This is local-only mode, and it stays signed out in every sense that
  /// matters: nothing here ever calls anything on [AuthProvider], so
  /// `auth.user` and `auth.state` are untouched, and in particular
  /// `main.dart`'s `trigger.setUser(auth.user?.uid)` keeps being called with
  /// `null` -- there is deliberately no synthesized uid anywhere on this path,
  /// which is what keeps `SyncTrigger` fully torn down (see its `setUser`
  /// doc) and every existing consent gate untouched. Setting this to `true`
  /// does not return early; [build] falls through to the SAME gate order a
  /// signed-in session runs (settings load, the lock gate, the two per-uid
  /// registrations -- which simply no-op for a null uid -- then onboarding),
  /// so the app lock still covers this session exactly as it covers any
  /// other, and [_appEverRendered] still guards it. Only the final content is
  /// different: it is wrapped in [CloudSyncUnavailableBanner], persistently,
  /// for as long as this field is true.
  ///
  /// Deliberately in-memory and NOT persisted to disk, so it cannot outlive
  /// this process, let alone this widget: [FirebaseAvailability] itself is
  /// decided exactly once per process and never re-evaluated (see its doc
  /// comment), so a genuine recovery is only ever observed on the NEXT
  /// launch, which constructs a fresh `_AppGateState` and starts this back at
  /// `false` -- there is no scenario in which persisting it across launches
  /// could do anything but make a hatch that is meant to be unreachable when
  /// Firebase is fine into one that momentarily still is, on stale
  /// information. Re-offering the choice every launch is the safe direction;
  /// the cost is a repeated tap during a long outage, not a bypass.
  bool _localOnly = false;

  /// The marker read is a network round-trip, and it must not become one the
  /// user waits on. Nothing here blocks a build: the read is issued from a
  /// post-frame callback and the app renders normally until it lands, so the
  /// common path (no request on record — nearly everyone) costs one small
  /// document read off the critical path and no added latency at all. If it
  /// errors, times out, or the build has no Firebase app, the result is "no
  /// request", i.e. show the app: this notice must never be able to lock
  /// someone out of their own tracker.
  static const _deletionCheckTimeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Engaging the lock on background lives in [AppLock] now, because the lock
  /// is rendered there; this observer is left with the resume-sync half.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      // Pull anything logged on another device while we were away.
      context.read<SyncTrigger>().syncNow();
    }
  }

  /// Whether the app lock is currently covering the app — the one thing nothing
  /// in this widget may raise a route on top of.
  ///
  /// A single read of [AppLock], which owns that state, rather than a local
  /// re-derivation from a `_locked` flag and a fresh `appLockEnabled` read. Two
  /// expressions for one question is two things that can drift, and this is the
  /// question a security fix depends on. (The earlier comment here justified the
  /// re-read by claiming "a sync can land a settings document that turns app
  /// lock off" — that is false: `SyncService` never sends or applies
  /// `appLockEnabled`, which is deliberately device-local. The guard was right;
  /// only its stated reason was wrong, and a wrong rationale in a
  /// security-critical comment is what the next author reasons from.)
  ///
  /// Not listening: this is sampled from an `await` resumption, not rendered
  /// from. [build] does the listening read.
  bool _lockGateShowing(BuildContext context) =>
      AppLock.isLocked(context, listen: false);

  /// Offers to upload pre-existing local logs the first time an account signs
  /// in on this device. Runs after the frame so it can show a modal sheet.
  void _maybePromptClaim(BuildContext context, String? uid) {
    if (uid == null || _claimPromptShownFor == uid) return;
    _claimPromptShownFor = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final trigger = context.read<SyncTrigger>();
      // Only ask when there is local data to ask about. Checked first because
      // it is a fast local read and it rules the prompt out for most signed-in
      // rebuilds (a fresh account with an empty device), which then never
      // reach `ClaimPreference`'s secure-storage read below.
      //
      // Deliberately `SyncTrigger.hasLocalDataToClaim()` and NOT a daily-log
      // count: `SyncService` pushes the settings document too, so a device
      // with no logged days but real health settings (pregnancy state among
      // them) has something to consent to. This MUST stay the same predicate
      // `SyncTrigger.setUser` gates on — if the two disagree, the account is
      // either gated and never prompted (sync silently off forever) or
      // prompted about nothing. The count below is only for the sheet's copy.
      if (!await trigger.hasLocalDataToClaim() || !context.mounted) return;
      final count = (await DailyLogRepository(db).getAll()).length;
      if (!context.mounted) return;
      // "Already answered" is per-ACCOUNT, not per-device: a record belonging
      // to a DIFFERENT uid must not suppress this genuinely new question, and
      // `AppSettings.lastSyncedAt` (device-global — it stays non-null once ANY
      // account has synced here) must not be consulted at all.
      //
      // Wrapped because this is the one secure-storage call on this path that
      // isn't already inside `SyncTrigger.setUser`'s try/catch, and an
      // exception escaping an `addPostFrameCallback` closure is an unhandled
      // async error: the prompt would never appear while the sync gate stayed
      // set, i.e. sync silently off with no way to turn it on. Failing toward
      // SHOWING the prompt costs at most a repeated question.
      ClaimRecord? record;
      try {
        record = await trigger.claimOnRecord();
      } catch (_) {
        record = null;
      }
      if (record?.uid == uid) return;
      if (!context.mounted) return;
      // The lock can engage BETWEEN this callback being scheduled and this
      // line: every `await` above is a suspension point, and the app can be
      // backgrounded in between. [AppLock] would keep the sheet out of sight
      // even so, but a modal question must not be *asked* of a session that
      // cannot answer it. Forget the uid so the question is raised again from
      // `build` the moment the lock lifts; dropping it silently would leave the
      // account gated with no way to be asked, and persisting anything here
      // would be a decision the user never made.
      if (_lockGateShowing(context)) {
        _claimPromptShownFor = null;
        return;
      }
      final upload = await showClaimLocalDataSheet(context, dayCount: count);
      // null is NOT "declined". The sheet returns null only when it was
      // dismissed without an answer (the Android system back button is not
      // blocked by `isDismissible: false`; `PopScope` now blocks it, but a
      // dismissal must still be safe). Collapsing that to `false` wrote a
      // durable, uid-scoped decline the user never made, and they would never
      // be asked again. Persist nothing and leave the sync gate set: the
      // question comes back next launch.
      if (upload == null || !context.mounted) return;
      // `resolveClaim` (not a bare `syncNow`): `true` records the claim,
      // clears SyncTrigger's pending-claim gate and runs the deferred sync;
      // `false` records the decline for this uid and leaves the gate set so
      // nothing pushes the declined history later.
      await trigger.resolveClaim(upload: upload);
    });
  }

  /// Looks for a deletion request on record for the signed-in account.
  ///
  /// Deliberately registered AFTER [_maybePromptClaim] in `build`, and it does
  /// not touch that flow: the claim prompt's sequencing (post-frame callback,
  /// `hasLocalDataToClaim()` first, per-uid record check, null ≠ declined) is
  /// load-bearing against the pre-consent upload race and is left exactly as
  /// it was. The two can overlap only for an account that requested deletion
  /// from ANOTHER device and still has local data here, and that overlap is
  /// harmless: `SyncService.syncNow` refuses to run for an account with a
  /// marker on record, so answering the claim prompt pushes nothing.
  void _maybeCheckDeletion(String? uid) {
    if (uid == null || _deletionCheckedFor == uid) return;
    _deletionCheckedFor = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      DeletionRequest? request;
      try {
        request =
            await widget.pendingDeletion(uid).timeout(_deletionCheckTimeout);
      } catch (_) {
        // Fail toward showing the app. Offline this is also the reachable
        // false negative: a user inside the grace window sees no notice at all
        // until they have a connection. Under-warning is the only direction
        // that is safe here — the binding gate is the marker itself, which
        // `SyncService` re-reads on every run.
        request = null;
      }
      if (!mounted || request == null || _deletionCheckedFor != uid) return;
      setState(() => _pendingDeletion = request);
    });
  }

  /// Withdraws the request, then pulls the account's data back down.
  ///
  /// The sync is not incidental. `SyncTrigger.resume()` returns immediately
  /// unless this session is the one that suspended — which it is not, in a
  /// fresh session after signing back in — so without an explicit [syncNow]
  /// the user would sit on the device they wiped, reading "Not synced yet",
  /// until they background and foreground the app. The provider reloads follow
  /// for the same reason: `SyncService` writes straight to drift and nothing
  /// tells the in-memory providers to re-read.
  Future<void> _cancelPendingDeletion(BuildContext context, String uid) async {
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    await widget.cancelDeletion(uid); // throws → the screen reports it
    if (!mounted) return;
    setState(() => _pendingDeletion = null);
    await trigger.syncNow();
    if (!mounted) return;
    await settings.load();
    await logs.load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Cold start: Firebase restores the session asynchronously. Showing a
    // splash here avoids a flash of the sign-in form for an already-signed-in
    // user.
    if (auth.state == AuthState.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // An account is required (design spec §7.1) -- UNLESS [_localOnly] is
    // already set, in which case this is not a fresh signed-out state to wall
    // off but the local-only session itself continuing; fall through to the
    // same gate order every other state runs, below.
    if (auth.state == AuthState.signedOut && !_localOnly) {
      // Forget which account was asked: whoever signs in next — including the
      // same account, if it never answered — gets the question again.
      _claimPromptShownFor = null;
      // Same reasoning for the marker: the next account to sign in here is a
      // different question, and a stale answer must not carry over.
      _deletionCheckedFor = null;
      _pendingDeletion = null;
      // The ONLY place that decides whether the "continue without syncing"
      // hatch is offered -- see [_localOnly]'s doc comment for why this reads
      // [FirebaseAvailability] and nothing else. Nullable + defaulted `true`
      // for the same reason `AccountSection` reads it the same way: harnesses
      // that build `AppGate` without planting the provider (most of this
      // file's own test suite) must see the ordinary, hatch-free sign-in
      // wall, not an unintentionally-open escape hatch.
      final firebaseAvailable =
          context.watch<FirebaseAvailability?>()?.available ?? true;
      return SignInScreen(
        showContinueWithoutSync: !firebaseAvailable,
        onContinueWithoutSync:
            firebaseAvailable ? null : () => setState(() => _localOnly = true),
      );
    }

    final settings = context.watch<SettingsProvider>();

    // Wait for settings to load to avoid a flash of the wrong screen.
    if (!settings.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // The lock is rendered by [AppLock], above the Navigator, so it covers
    // whatever this method returns AND every route pushed on top of it. Nothing
    // here returns `LockScreen` any more. Once the user has been past the lock
    // once, nothing here tears the app down for it either: the tree stays
    // MOUNTED (offstage) while locked, which is what puts them back on the same
    // screen, in the same sheet, at the same scroll position on unlock.
    //
    // What is still gated on the lock is the two REGISTRATIONS below, and that
    // gating is the ordering three fix rounds converged on. `_maybePromptClaim`
    // raises a Navigator route and `_maybeCheckDeletion` issues a network read;
    // neither should happen to a session that cannot see or answer either. An
    // unlock (PIN or biometric — both land on the same `setState` in [AppLock])
    // rebuilds this widget through `AppLock.isLocked`'s dependency and raises
    // the prompt then. With app lock off, control arrives here on the same
    // build it always did.
    //
    // The deletion notice being BELOW this is the same ordering, for the same
    // reason: an earlier revision put it first, reasoning that a deletion
    // request clears the PIN and resets settings so app lock must be off — true
    // only on the REQUESTING device. On a second device signed into the same
    // account the PIN and settings are untouched, and the notice would hand
    // whoever holds the locked phone the fact and date of the deletion, a
    // cancel button that pulls the whole cloud history back onto the device,
    // and a sign-out — a pre-lock exit that chains into the claim sheet under a
    // different account.
    //
    // Their relative order and per-uid keying are unchanged and load-bearing:
    // see `_maybePromptClaim` (the pre-consent upload race lives in exactly this
    // sequencing) and `_maybeCheckDeletion`.
    final locked = AppLock.isLocked(context);
    // Nothing of the app starts up behind a lock it has never been past; after
    // that first unlock the tree stays mounted so it can be restored. See
    // [_appEverRendered]. The placeholder is never seen — [AppLock] is over it.
    if (locked && !_appEverRendered) return const Scaffold();
    if (!locked) {
      _appEverRendered = true;
      _maybePromptClaim(context, auth.user?.uid);
      _maybeCheckDeletion(auth.user?.uid);
    }

    // A pending deletion outranks onboarding, and that ordering IS the fix:
    // `deleteAllData()` resets `onboardingComplete`, so a user who requested
    // deletion and signs back in inside the grace window would otherwise walk
    // the whole first-run flow for an account scheduled for erasure and never
    // be told — Settings → Account, the only other disclosure, is somewhere
    // they have no reason to go.
    //
    // Dismissible, and that is not a weakening of the disclosure. An
    // unconditional early return locked the user out of their own LOCAL tracker
    // for the entire grace window unless they cancelled the deletion — worst on
    // the second device, which was never wiped, still holds the full history in
    // drift, and whose owner never asked for anything to happen to it. The
    // request is about the SERVER copy; nothing promised the device stops
    // working. Dismissal is session-only (`_deletionCheckedFor` keeps the read
    // from re-issuing, but a fresh gate re-reads), so the notice comes back on
    // the next launch.
    final pendingDeletion = _pendingDeletion;
    final uid = auth.user?.uid;
    if (pendingDeletion != null && uid != null) {
      return DeletionPendingScreen(
        request: pendingDeletion,
        onCancel: () => _cancelPendingDeletion(context, uid),
        onSignOut: () => context.read<AuthProvider>().signOut(),
        onDismiss: () => setState(() => _pendingDeletion = null),
      );
    }

    // First run: onboarding before anything else. A brand-new local-only user
    // (no account, Firebase down) walks this exactly like anyone else — the
    // banner below covers it too, so onboarding is never a moment where the
    // reduced-functionality state goes unmentioned.
    final content =
        settings.onboardingComplete ? const AppShell() : const OnboardingScreen();
    if (_localOnly) {
      // Persistent, not a one-off snackbar: it must stay on screen for the
      // whole local-only session, across every tab, exactly as long as
      // [_localOnly] is true (i.e. until the next launch — see its doc
      // comment). Wraps [content] rather than living inside `AppShell`, which
      // would need a change to a file this task does not touch and would tie
      // a device-availability concern into the tab shell's own widget tree.
      return Column(
        children: [
          const CloudSyncUnavailableBanner(),
          Expanded(child: content),
        ],
      );
    }
    return content;
  }
}
