import 'product_type.dart';

/// An in-progress product-change session: what is in use, when it went in, and
/// the target the user chose.
///
/// This is the app's only intra-day entity. It is deliberately **ephemeral** —
/// exactly one may exist at a time, and ending it leaves no record. That is
/// what keeps the feature clear of a schema migration, of Firestore (where a
/// minute-resolution log of intimate acts would sit in plaintext), and of the
/// retention and export questions a history table would drag in.
class ProductSession {
  const ProductSession({
    required this.insertedAt,
    required this.product,
    required this.interval,
  });

  final DateTime insertedAt;
  final ProductType product;

  /// The target the user chose — never inferred from flow, cycle day or phase.
  final Duration interval;

  /// When the reminder is aimed at. Not a deadline the app authored, and never
  /// rendered as time *remaining*.
  DateTime get dueAt => insertedAt.add(interval);

  /// Time since [insertedAt], floored at zero. Always recomputed from the
  /// stored timestamp rather than accumulated, so a locked screen, a Doze
  /// window or a backgrounded app cannot make it drift.
  Duration elapsedAt(DateTime now) {
    final d = now.difference(insertedAt);
    return d.isNegative ? Duration.zero : d;
  }

  bool isPastTargetAt(DateTime now) => !now.isBefore(dueAt);

  /// How far past the target we are, floored at zero. Drives the disclosure
  /// that a reminder may not have arrived — the one thing that converts a
  /// silently-dropped notification from an invisible failure into a visible one.
  Duration overrunAt(DateTime now) {
    final d = now.difference(dueAt);
    return d.isNegative ? Duration.zero : d;
  }

  ProductSession copyWith({
    DateTime? insertedAt,
    ProductType? product,
    Duration? interval,
  }) =>
      ProductSession(
        insertedAt: insertedAt ?? this.insertedAt,
        product: product ?? this.product,
        interval: interval ?? this.interval,
      );

  @override
  bool operator ==(Object other) =>
      other is ProductSession &&
      other.insertedAt == insertedAt &&
      other.product == product &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(insertedAt, product, interval);

  @override
  String toString() =>
      'ProductSession(${product.name}, $insertedAt, ${interval.inMinutes}m)';
}
