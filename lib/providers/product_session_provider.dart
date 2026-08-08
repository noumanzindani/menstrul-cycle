import 'package:flutter/foundation.dart';

import '../data/product_session_repository.dart';
import '../models/product_session.dart';
import '../models/product_type.dart';
import '../services/notification_service.dart';
import '../services/product_timer_payload.dart';
import '../services/product_timer_plan.dart';

/// Owns the in-progress product-change session and keeps its notification slots
/// in step with it.
///
/// Deliberately separate from `ReminderProvider`: that class is about scheduled
/// clock reminders, and a session is not one. Keeping them apart also means
/// Home rebuilds on a session change without rebuilding on every reminder edit.
class ProductSessionProvider extends ChangeNotifier {
  ProductSessionProvider(this._repo);
  final ProductSessionRepository _repo;

  ProductSession? _session;
  ProductSession? get session => _session;
  bool get hasSession => _session != null;

  /// Reloads from the database. Also the resync point after a background
  /// isolate has written — a notification action runs in its own isolate with
  /// its own connection, so in-memory state here is stale until this runs.
  Future<void> load() async {
    _session = await _repo.get();
    notifyListeners();
  }

  /// Starts a session. Returns false — and starts nothing — if [interval] is
  /// past the product's manufacturer cap or is not positive.
  ///
  /// A refusal, not a clamp. Silently rewriting the user's number would hide
  /// that the app declined, and the whole point of the cap is that the app will
  /// never help someone exceed what the packaging says.
  Future<bool> start(
    ProductType product, {
    Duration? interval,
    DateTime? now,
  }) async {
    final chosen = interval ?? product.defaultDuration;
    if (chosen <= Duration.zero || chosen > product.maxDuration) return false;

    await _write(ProductSession(
      insertedAt: now ?? DateTime.now(),
      product: product,
      interval: chosen,
    ));
    return true;
  }

  /// "Changed it" — swaps in a fresh one of the same product, carrying over the
  /// duration the user chose rather than resetting to the default. This is the
  /// one-tap-per-bathroom-visit path, from the card or the notification action.
  ///
  /// A no-op when nothing is running, so a stale notification cannot conjure a
  /// session out of nothing.
  Future<void> changed({DateTime? now}) async {
    final current = _session;
    if (current == null) return;
    await _write(current.copyWith(insertedAt: now ?? DateTime.now()));
  }

  /// "Removed" — ends the session without starting another.
  Future<void> removed() async {
    await _repo.end();
    _session = null;
    await NotificationService.cancelProductTimer();
    notifyListeners();
  }

  /// Re-arms the notification slots from the stored `insertedAt`. Called on app
  /// resume: alarms do not survive a force-stop, and slots that passed while
  /// the app was closed must not be re-scheduled into the past.
  Future<void> reschedule({DateTime? now}) async {
    await _applyPlan(now ?? DateTime.now());
  }

  Future<void> _write(ProductSession session) async {
    await _repo.start(session);
    _session = session;
    await _applyPlan(DateTime.now());
    notifyListeners();
  }

  /// Recomputes the plan and hands it to the platform. An absent session yields
  /// an empty plan, which cancels every slot — the plan can never resurrect a
  /// reminder for a session that is over.
  Future<void> _applyPlan(DateTime now) async {
    final current = _session;
    await NotificationService.applyProductTimerPlan(
      ProductTimerPlan.planIfEnabled(
        enabled: current != null,
        session: current,
        now: now,
      ),
      payload:
          current == null ? null : encodeSessionStamp(current.insertedAt),
    );
  }
}
