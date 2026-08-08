import 'dart:convert';

import '../models/product_session.dart';
import '../models/product_type.dart';

/// Longest interval any payload may claim. The real per-product caps (8h for a
/// tampon, 12h for a cup) are enforced where the user picks a duration; this is
/// only a corruption bound, so a garbled blob degrades to "no session" instead
/// of a timer that runs for a year.
const Duration _maxDecodableInterval = Duration(hours: 24);

/// Serialises the in-progress session for the `Reminders.payload` TEXT column.
///
/// `insertedAt` is stored as **epoch milliseconds**, not a wall clock. An
/// elapsed timer cares about an instant: reconstructing a local date-time would
/// drift by an hour across a DST boundary and break entirely if the device
/// changes time zone mid-session.
String encodeProductSession(ProductSession session) => jsonEncode({
      'insertedAt': session.insertedAt.millisecondsSinceEpoch,
      'product': session.product.name,
      'intervalMinutes': session.interval.inMinutes,
    });

/// Decodes [encodeProductSession]. Returns null for a null, empty, malformed,
/// or out-of-range payload rather than throwing.
///
/// The no-throw contract is not defensive habit: this runs in a bare background
/// isolate where an exception is invisible, so bad input has to fail quietly.
/// Same reasoning as `decodeCheckInPayload`.
ProductSession? decodeProductSession(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;

  final Object? raw;
  try {
    raw = jsonDecode(payload);
  } catch (_) {
    return null;
  }
  if (raw is! Map) return null;

  final insertedAt = raw['insertedAt'];
  final minutes = raw['intervalMinutes'];
  if (insertedAt is! int || minutes is! int) return null;

  final product = productTypeFromName(
      raw['product'] is String ? raw['product'] as String : null);
  if (product == null) return null;

  if (minutes <= 0 || minutes > _maxDecodableInterval.inMinutes) return null;

  return ProductSession(
    insertedAt: DateTime.fromMillisecondsSinceEpoch(insertedAt),
    product: product,
    interval: Duration(minutes: minutes),
  );
}

/// Encodes which session a notification belongs to, for its `payload` string.
///
/// Plain decimal epoch millis — no JSON, no dependencies — so it survives the
/// platform round-trip through a String channel intact, the same way the
/// check-in payload uses a bare `yyyy-MM-dd`.
String encodeSessionStamp(DateTime insertedAt) =>
    insertedAt.millisecondsSinceEpoch.toString();

/// Decodes [encodeSessionStamp]. Null for anything unparseable; never throws.
DateTime? decodeSessionStamp(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  final millis = int.tryParse(payload.trim());
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

/// Whether [payload] identifies [current] — the guard that stops a notification
/// left over from an earlier session from ending the one running now.
///
/// Fails closed: an unparseable stamp, or no current session, is never a match.
bool isStampFor(String? payload, DateTime? current) {
  if (current == null) return false;
  final stamped = decodeSessionStamp(payload);
  if (stamped == null) return false;
  return stamped.isAtSameMomentAs(current);
}
