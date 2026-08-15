import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/sync_merge.dart';

/// Last-write-wins at the WHOLE-DAY level. Field-level merge was rejected in
/// the spec: `encodeDayTags` is a full REPLACE, so merging individual tags from
/// two devices would synthesise a tag set the user never authored on either.
/// Whole-document LWW can lose an edit; field merge can INVENT one. For a
/// health log, losing is safer than inventing.
void main() {
  final earlier = DateTime(2026, 8, 4, 10);
  final later = DateTime(2026, 8, 4, 11);

  test('a newer remote wins', () {
    expect(decideMerge(local: earlier, remote: later), MergeDecision.takeRemote);
  });

  test('a newer local wins', () {
    expect(decideMerge(local: later, remote: earlier), MergeDecision.keepLocal);
  });

  test('identical timestamps change nothing', () {
    expect(
      decideMerge(local: earlier, remote: earlier),
      MergeDecision.unchanged,
    );
  });

  test('a day that exists only remotely is taken', () {
    expect(decideMerge(local: null, remote: later), MergeDecision.takeRemote);
  });

  test('a day that exists only locally is kept', () {
    expect(decideMerge(local: later, remote: null), MergeDecision.keepLocal);
  });

  test('neither side present is unchanged', () {
    expect(decideMerge(local: null, remote: null), MergeDecision.unchanged);
  });

  test('a future-dated remote still resolves without throwing', () {
    // `updatedAt` comes from device time, so a device with a badly wrong clock
    // can produce a timestamp far in the future. Sync must resolve it, not
    // crash — the wrong side winning is recoverable, a crash loop is not.
    final future = DateTime(2099, 1, 1);
    expect(decideMerge(local: later, remote: future), MergeDecision.takeRemote);
  });
}
