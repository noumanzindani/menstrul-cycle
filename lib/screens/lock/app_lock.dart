import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import 'lock_screen.dart';

/// The app lock, installed ABOVE the [Navigator] through `MaterialApp.builder`
/// so that it covers every route.
///
/// This placement is the whole point. [LockScreen] used to be returned from
/// `AppGate.build`, which meant it replaced the content of the `home:` route and
/// nothing else. Bottom sheets, dialogs, pushed screens and snackbars are
/// Navigator ROUTES on the same root navigator, so they rendered *above* the
/// lock: backgrounding the app with the claim sheet open handed whoever held the
/// locked phone the disclosure that this device holds N days of
/// menstrual-health logs and a one-tap "Add to my account" that uploaded them,
/// with no PIN. Every screen pushed from `AppShell` (the day log, medications,
/// reminders, the calendar's day sheet) had the same hole. Guarding each
/// individual `show*` call site is a losing pattern — it was tried three times
/// and a variant survived each round. `MaterialApp.builder` runs between the
/// app's `Theme`/`ScaffoldMessenger` and the `Navigator`, so wrapping there
/// covers the navigator, its overlay, and therefore every route at once.
///
/// While locked the app is kept MOUNTED but [Offstage]: it is not laid out, not
/// painted, not hit-testable and not in the semantics tree (so a screen reader
/// cannot read it either), yet every `State`, scroll position and open route
/// survives — unlocking puts the user back exactly where they were, including
/// inside a sheet or a pushed screen. Replacing the tree instead would lose all
/// of that. `find` in a widget test skips offstage subtrees by default, so
/// `findsNothing` there means the same thing it means to the user.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child, this.lockNotifier});

  /// The whole app below `MaterialApp.builder` — in practice the [Navigator].
  final Widget child;

  /// Mirrors "is the lock up" out to an observer registered ABOVE
  /// `MaterialApp` (`_LockRouteGuard` in `main.dart`), so the Android back
  /// button can be swallowed before it ever reaches the root `Navigator`.
  ///
  /// This can't be done with a `didPopRoute` override living on [AppLock]
  /// itself — that was tried, and it doesn't work:
  /// `WidgetsBinding.handlePopRoute` consults its observers in REGISTRATION
  /// order (not newest-first — see the doc comment at
  /// `widgets/binding.dart:949`) and stops at the first one that returns
  /// `true`. `_WidgetsAppState` registers itself in `initState`, which the
  /// framework runs before any widget below `MaterialApp` — this one
  /// included — ever mounts, so `_WidgetsAppState`'s own `didPopRoute` (which
  /// calls `navigator.maybePop()`) is always consulted first and always wins
  /// while there is a route to pop. An observer that actually wants first
  /// refusal has to be registered by something that is itself an ANCESTOR of
  /// `MaterialApp`.
  ///
  /// [AppLock] only ever WRITES to this — [build] is the one place "locked"
  /// is computed (`_locked && enabled`), and that exact value is fed here,
  /// not a second hand-rolled expression for the same question. `null` in
  /// every harness that doesn't need back-button coverage — several tests
  /// call `AppLock.wrap` directly (the claim-prompt and deletion-notice
  /// suites), and a write to a null notifier is just skipped.
  final ValueNotifier<bool>? lockNotifier;

  /// The exact expression `main.dart` hands to `MaterialApp.builder` in every
  /// harness that isn't specifically exercising the back-button fix.
  ///
  /// Exposed as a named function so the app and every widget-test harness pass
  /// the SAME thing; a harness that hand-rolled its own wrapper would be testing
  /// a lock the app does not have. `main.dart` itself does not use this
  /// directly — it needs to hand in a [lockNotifier] owned by `_LockRouteGuard`
  /// — but constructs `AppLock` the same way otherwise.
  static Widget wrap(BuildContext context, Widget? child) =>
      AppLock(child: child ?? const SizedBox.shrink());

  /// Whether the lock is currently covering the app.
  ///
  /// This is the ONE owner of that answer. `AppGate` used to re-derive it from
  /// its own `_locked` flag combined with a fresh `appLockEnabled` read, which
  /// meant the same question was expressed in two places and could drift; it now
  /// reads this instead. Nothing else may compute "is the lock up?" from parts.
  ///
  /// [listen] registers a dependency, so a widget that reads it rebuilds when
  /// the lock engages or lifts. Pass `false` from a callback that is only
  /// sampling the current value (an `await` resumption, say) rather than
  /// rendering from it.
  ///
  /// Returns `false` with no [AppLock] above: a tree with no lock installed
  /// cannot be locked. The app installs it in `main.dart`, and
  /// `test/app_lock_route_coverage_test.dart` pumps the real `LunaTrackApp` —
  /// not a hand-built harness — precisely so that wiring cannot go missing
  /// unnoticed.
  static bool isLocked(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<_LockScope>()
        : context.getInheritedWidgetOfExactType<_LockScope>();
    return scope?.locked ?? false;
  }

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool _locked = false;

  /// Latched the first time app lock is known to be enabled, so the lock is
  /// applied once on cold start and never re-applied behind the user's back
  /// (an unlock followed by an unrelated settings rebuild must not re-lock).
  bool _initialLockApplied = false;

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

  /// Unchanged from the logic this moved out of `AppGate`: the lock engages
  /// when the app leaves the foreground, and only when the user asked for it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!mounted) return;
      if (context.read<SettingsProvider>().appLockEnabled) _lock();
    }
  }

  // The Android back button is handled by `_LockRouteGuard` in `main.dart`,
  // an observer registered ABOVE `MaterialApp` — see the doc comment on
  // [AppLock.lockNotifier] for why a `didPopRoute` override living here
  // (which this class used to have) is never actually consulted.

  void _lock() {
    if (_locked) return;
    // Drop focus BEFORE the app goes offstage. This is NOT about layout —
    // `RenderOffstage.performLayout` calls `child.layout` regardless of
    // whether it's offstage (only `sizedByParent`/paint/hit-test/semantics
    // are suppressed), so a focused `EditableText` would still be laid out
    // fine. This is about the NATIVE soft keyboard: without dropping focus
    // first, it would stay open and sit visually on top of the lock.
    // `ExcludeFocus` below keeps focus out while the lock is up.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _locked = true);
    // Publish to `_LockRouteGuard` HERE, not only from `build` below.
    //
    // This runs from `didChangeAppLifecycleState(paused)`, and
    // `SchedulerBinding.handleAppLifecycleStateChanged`
    // (scheduler/binding.dart:414-428) disables frames for
    // `hidden`/`paused`/`detached` by calling `_setFramesEnabledState(false)`
    // — after which `scheduleFrame()` (:947) early-returns
    // (`if (_hasScheduledFrame || !framesEnabled) return;`) without ever
    // setting `_hasScheduledFrame`. `setState` above therefore does not
    // result in a drawn frame: the `markNeedsBuild` it triggers requests one,
    // but that request is exactly the no-op `scheduleFrame()` call just
    // described. No frame runs — so `build` does not run, and the
    // `lockNotifier` write down in `build` does not run either — until the
    // FIRST FRAME AFTER RESUME, whenever the engine gets around to producing
    // one. In that entire window the guard in `main.dart` would keep
    // consulting a stale `false` and decline to swallow the back button,
    // letting `_WidgetsAppState` pop the hidden route instead
    // (`test/app_lock_back_button_test.dart`'s
    // "before the first post-resume frame" case is the regression test for
    // exactly this).
    //
    // Writing here does not introduce a second expression for "am I locked":
    // `_lock` is only ever reached with `appLockEnabled == true` (guarded in
    // `didChangeAppLifecycleState` above), so `locked` is definitionally
    // `true` at this call site — this is the same value `build` would
    // compute, published earlier rather than re-derived. `build` remains the
    // one place "locked" is COMPUTED (`_locked && enabled`); this is only an
    // earlier PUBLISH of a value already known here.
    widget.lockNotifier?.value = true;
  }

  @override
  Widget build(BuildContext context) {
    // Re-read rather than assumed from [_locked]: "locked" without "enabled" is
    // not a gate, and this is now the only place the two are combined.
    final enabled = context.watch<SettingsProvider>().appLockEnabled;

    // Lock once on the first build where app lock is known to be enabled. This
    // deliberately does not wait for a signed-in user: the lock now covers the
    // splash and the sign-in screen too, and the sign-in screen is exactly where
    // the claim sheet is raised from.
    if (enabled && !_initialLockApplied) {
      _initialLockApplied = true;
      _locked = true;
    }
    // The ONE expression for "is the lock actually up right now". Feed it to
    // every consumer below rather than letting any of them re-derive it — a
    // second hand-rolled copy of this exact question is what made the old
    // `didPopRoute` override silently drift out of sync with this one.
    final locked = _locked && enabled;
    widget.lockNotifier?.value = locked;

    return _LockScope(
      locked: locked,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Three wrappers, three separate leaks:
          //   Offstage      — no layout, no paint, no hit test, no semantics.
          //   TickerMode    — nothing animates behind a lock nobody can see.
          //   ExcludeFocus  — a hardware keyboard cannot traverse into it.
          ExcludeFocus(
            excluding: locked,
            child: TickerMode(
              enabled: !locked,
              child: Offstage(offstage: locked, child: widget.child),
            ),
          ),
          if (locked)
            _LockLayer(onUnlocked: () => setState(() => _locked = false)),
        ],
      ),
    );
  }
}

/// [LockScreen] plus the [Overlay] and [ScaffoldMessenger] it needs.
///
/// The lock is deliberately OUTSIDE the app's `Navigator` — that placement is
/// the whole fix — and therefore outside the `Overlay` that comes with it. An
/// `EditableText` (the PIN field) requires an `Overlay` ancestor for its
/// selection handles and magnifier, so the lock brings its own. It is scoped to
/// this widget: one overlay and one entry per lock episode, both dying with it.
///
/// It ALSO brings its own [ScaffoldMessenger], for a reason that is not
/// obvious from `LockScreen` alone: `MaterialApp` installs one app-wide
/// `ScaffoldMessenger` AROUND the entire output of `builder:` — i.e. around
/// this whole `AppLock` subtree, `_LockLayer` included. Without a
/// `ScaffoldMessenger` of its own here, `LockScreen`'s `Scaffold` finds and
/// registers with THAT SAME app-wide instance (`ScaffoldMessengerState`
/// walks up via `_ScaffoldMessengerScope`, and `AppLock` sits below it in the
/// tree), and — being a `Scaffold` with no ancestor `ScaffoldState` of its
/// own — is treated as a ROOT scaffold that immediately paints whatever
/// snackbar is pending. Concretely: a snackbar live when the app is
/// backgrounded, or raised by an in-flight async call (e.g.
/// `settings_screen._importHealth`, `account_section._enableSync`) that
/// completes after the lock has already engaged, rendered ON TOP of the lock
/// screen — readable, and if it carried a `SnackBarAction` (e.g.
/// `account_section._showError`'s 8-second "Retry", whose `onPressed` wipes
/// local data, clears the PIN and signs out), tappable, with no PIN. Wrapping
/// the `Overlay` in a fresh `ScaffoldMessenger` gives `LockScreen`'s own
/// registration nowhere else to go: it can only ever show a snackbar this
/// widget itself raises, which is never. `test/app_lock_snackbar_isolation_test.dart`
/// is the regression guard.
class _LockLayer extends StatefulWidget {
  const _LockLayer({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_LockLayer> createState() => _LockLayerState();
}

class _LockLayerState extends State<_LockLayer> {
  // Not disposed explicitly: an `OverlayEntry` may only be disposed after it
  // has been removed from its Overlay, and this one is never removed — the
  // Overlay it belongs to is unmounted wholesale when the lock lifts, taking
  // the entry with it.
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => LockScreen(onUnlocked: widget.onUnlocked),
  );

  @override
  Widget build(BuildContext context) =>
      ScaffoldMessenger(child: Overlay(initialEntries: [_entry]));
}

class _LockScope extends InheritedWidget {
  const _LockScope({required this.locked, required super.child});

  final bool locked;

  @override
  bool updateShouldNotify(_LockScope oldWidget) => oldWidget.locked != locked;
}
