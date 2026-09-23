import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `showRewarded` cannot run under `flutter_tester` (google_mobile_ads talks
/// over platform channels with no test handler), so its one timing rule is
/// pinned in the source instead.
///
/// `RewardedAd.show` completes when the ad APPEARS, not when it closes.
/// Returning straight after it read `earned` before the user could earn
/// anything: every watched ad came back declined and no conversation ever
/// started on a device.
String _showRewardedBody() {
  final src = File('lib/services/ad_service.dart').readAsStringSync();
  final start = src.indexOf('Future<RewardedOutcome> showRewarded(');
  final end = src.indexOf('Future<void> preloadInterstitial(', start);
  expect(start, isNonNegative, reason: 'showRewarded moved or was renamed');
  expect(end, greaterThan(start));
  return src.substring(start, end);
}

void main() {
  late String body;
  setUpAll(() => body = _showRewardedBody());

  test('the outcome is settled by the dismiss callback, not by show()', () {
    expect(body, contains('Completer<RewardedOutcome>()'));
    final show = body.indexOf('await ad.show(');
    expect(show, isNonNegative);
    final after = body.substring(show);
    expect(after, contains('return outcome.future;'));
    expect(after, isNot(contains('earned ? RewardedOutcome')),
        reason: 'reading `earned` after show() races the reward callback');
  });

  test('both terminal callbacks complete the outcome', () {
    for (final cb in [
      'onAdDismissedFullScreenContent',
      'onAdFailedToShowFullScreenContent',
    ]) {
      final at = body.indexOf(cb);
      expect(at, isNonNegative, reason: cb);
      final next = body.indexOf('},', at);
      expect(body.substring(at, next), contains('outcome.complete('),
          reason: '$cb must settle the outcome or the send hangs');
    }
  });

  test('a failure to show lets the user through', () {
    final at = body.indexOf('onAdFailedToShowFullScreenContent');
    expect(body.substring(at, body.indexOf('},', at)),
        contains('RewardedOutcome.unavailable'));
  });
}
