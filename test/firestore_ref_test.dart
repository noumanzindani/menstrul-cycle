import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/firestore_ref.dart';

/// LunaTrack MUST NOT use the `(default)` Firestore database: `hbgapp-c3c88` is
/// shared with four unrelated apps, and `(default)` has ONE project-wide
/// ruleset. A named database carries its own rules. This test pins the id so a
/// rename can't silently move menstrual data under someone else's rules.
void main() {
  test('the LunaTrack database id is the named database, not (default)', () {
    expect(kLunaDatabaseId, 'lunatrack');
    expect(kLunaDatabaseId, isNot('(default)'));
  });
}
