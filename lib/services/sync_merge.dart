/// What sync should do with one day, given both sides' last-modified times.
enum MergeDecision {
  /// Overwrite the local row with the remote document.
  takeRemote,

  /// Keep (and push) the local row.
  keepLocal,

  /// Both sides agree, or neither exists.
  unchanged,
}

/// Last-write-wins over a whole day document.
///
/// Deliberately NOT field-level: `encodeDayTags` rebuilds the entire symptoms
/// blob from form state, so merging individual tags across devices would
/// fabricate a combination the user never entered. See the design spec §6.
///
/// Timestamps come from device clocks, so this must tolerate skew — including
/// a remote timestamp in the future — without throwing.
MergeDecision decideMerge({DateTime? local, DateTime? remote}) {
  if (local == null && remote == null) return MergeDecision.unchanged;
  if (local == null) return MergeDecision.takeRemote;
  if (remote == null) return MergeDecision.keepLocal;
  if (remote.isAfter(local)) return MergeDecision.takeRemote;
  if (local.isAfter(remote)) return MergeDecision.keepLocal;
  return MergeDecision.unchanged;
}
