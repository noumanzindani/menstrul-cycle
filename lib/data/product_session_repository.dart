import '../models/enums.dart';
import '../models/product_session.dart';
import '../services/product_timer_payload.dart';
import 'reminder_repository.dart';

/// Stores the single in-progress product-change session.
///
/// There is no `ProductChanges` table and no schema bump. The session rides one
/// dormant `Reminders` row of type [ReminderType.productChange], with its state
/// in the free-form `payload` column. Three properties come free with that
/// choice, and each was a requirement rather than a happy accident:
///
///  * `Reminders` is deliberately excluded from Firestore sync, so a
///    minute-resolution record of an intimate act never leaves the device.
///  * `AppDatabase.deleteAllData()` already clears the table, so "erase
///    everything" stays true without a new call site.
///  * `ReminderRepository.upsert` is already one-row-per-type, so the
///    at-most-one-session invariant is enforced by tested code.
///
/// The invariant matters: `getByType` uses `getSingleOrNull`, which *throws* on
/// two rows. Always upsert, never insert.
class ProductSessionRepository {
  ProductSessionRepository(this._reminders);
  final ReminderRepository _reminders;

  /// The running session, or null if none. A corrupt payload also reads as
  /// null — degrading to "no session" is always safer than surfacing a timer
  /// built from garbage.
  Future<ProductSession?> get() async {
    final row = await _reminders.getByType(ReminderType.productChange);
    if (row == null) return null;
    return decodeProductSession(row.payload);
  }

  /// Starts (or replaces) the session. `hour`/`minute` are the documented 0/0
  /// sentinel — a session has no time-of-day.
  Future<void> start(ProductSession session) => _reminders.upsert(
        type: ReminderType.productChange,
        enabled: true,
        hour: 0,
        minute: 0,
        payload: encodeProductSession(session),
      );

  /// Ends the session by removing the row. Deleting rather than disabling means
  /// a finished session leaves nothing behind to be restored, re-read, or
  /// exported.
  Future<void> end() => _reminders.deleteByType(ReminderType.productChange);
}
