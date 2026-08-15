/// The menstrual products a change timer can run for.
///
/// Unlike the enums in `models/enums.dart`, this one is persisted **by name**
/// inside the session payload JSON rather than by integer index, so declaration
/// order carries no meaning and values may be reordered or inserted freely.
/// Decode through [productTypeFromName], which returns null rather than
/// throwing — the payload is read in a background isolate where an exception is
/// invisible.
library;

enum ProductType {
  pad,
  tampon,
  cupOrDisc,
  periodUnderwear,
}

/// Durations, caps and the copy that attributes them.
///
/// The whole point of this extension is that a duration is a pure function of
/// the product type alone. It never takes logs, a prediction, or a cycle phase:
/// varying a wear time by predicted flow would turn a timer into a synthesized
/// clinical recommendation, which is the same false-precision hazard the
/// fertility surfaces already refuse.
extension ProductTypeInfo on ProductType {
  String get label => switch (this) {
        ProductType.pad => 'Pad',
        ProductType.tampon => 'Tampon',
        ProductType.cupOrDisc => 'Cup / disc',
        ProductType.periodUnderwear => 'Period underwear',
      };

  /// Pre-selected duration. Deliberately shorter than [maxDuration] — a
  /// reminder that lands exactly on the manufacturer maximum is a violation
  /// notice, not something the user can still act on.
  Duration get defaultDuration => switch (this) {
        ProductType.pad => const Duration(hours: 4),
        ProductType.tampon => const Duration(hours: 4),
        ProductType.cupOrDisc => const Duration(hours: 8),
        ProductType.periodUnderwear => const Duration(hours: 8),
      };

  /// The longest duration the picker will accept. For [hasWearLimit] products
  /// this is manufacturer-stated guidance and the app refuses to go past it;
  /// for the others it is only a UI sanity bound and must never be presented
  /// as safety guidance.
  Duration get maxDuration => switch (this) {
        ProductType.tampon => const Duration(hours: 8),
        ProductType.pad ||
        ProductType.cupOrDisc ||
        ProductType.periodUnderwear =>
          const Duration(hours: 12),
      };

  /// Whether [maxDuration] reflects a manufacturer wear limit (tampons, cups
  /// and discs) rather than an arbitrary UI bound (pads, period underwear).
  bool get hasWearLimit =>
      this == ProductType.tampon || this == ProductType.cupOrDisc;

  /// Why the cap exists, attributed to its source. LunaTrack states elapsed
  /// time and the target the user chose; it never authors a wear time of its
  /// own. Null for products with no manufacturer limit.
  String? get capNote => switch (this) {
        ProductType.tampon =>
          'Tampon packaging generally says not to leave one in longer than '
              '8 hours.',
        ProductType.cupOrDisc =>
          'Cup manufacturers generally say to empty it at least every '
              '12 hours.',
        ProductType.pad || ProductType.periodUnderwear => null,
      };
}

/// Decodes a persisted [ProductType] name. Returns null for an unknown or
/// missing name instead of throwing, so a payload written by a newer build (or
/// a corrupted one) degrades to "no session" rather than crashing the isolate
/// that read it.
ProductType? productTypeFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final t in ProductType.values) {
    if (t.name == name) return t;
  }
  return null;
}
