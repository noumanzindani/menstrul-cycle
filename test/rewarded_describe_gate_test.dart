import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/services/rewarded_describe_gate.dart';

/// The decision half of the rewarded-ad gate, kept clear of AdMob so it can be
/// tested at all: `google_mobile_ads` talks over platform channels that have
/// no handler under `flutter_tester`.
void main() {
  Future<bool> run({
    required bool premium,
    bool confirms = true,
    RewardedOutcome outcome = RewardedOutcome.earned,
    List<String>? calls,
  }) =>
      earnOneConversation(
        premium: premium,
        confirm: () async {
          calls?.add('confirm');
          return confirms;
        },
        showAd: () async {
          calls?.add('showAd');
          return outcome;
        },
      );

  test('premium proceeds without a prompt or an ad', () async {
    final calls = <String>[];
    expect(await run(premium: true, calls: calls), isTrue);
    expect(calls, isEmpty, reason: 'premium is precisely the absence of ads');
  });

  test('earning the reward proceeds', () async {
    final calls = <String>[];
    expect(await run(premium: false, calls: calls), isTrue);
    expect(calls, ['confirm', 'showAd']);
  });

  test('declining the prompt never loads an ad', () async {
    final calls = <String>[];
    expect(await run(premium: false, confirms: false, calls: calls), isFalse);
    expect(calls, ['confirm'],
        reason: 'the opt-in IS the policy requirement; an ad shown to someone '
            'who said no is not a rewarded ad');
  });

  test('abandoning the ad part-way does NOT proceed', () async {
    expect(
      await run(premium: false, outcome: RewardedOutcome.declined),
      isFalse,
    );
  });

  test('an ad that could not be served proceeds anyway', () async {
    expect(
      await run(premium: false, outcome: RewardedOutcome.unavailable),
      isTrue,
      reason: 'no-fill is routine and is not the user\'s doing; an ad outage '
          'must not brick a feature they consented to',
    );
  });
}
