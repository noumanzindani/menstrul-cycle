/// How a rewarded ad ended.
///
/// [declined] and [unavailable] are kept apart deliberately: one is the user
/// choosing not to watch, the other is AdMob having nothing to serve. They
/// look identical at the call site and must not be treated alike -- see
/// [earnOneConversation].
enum RewardedOutcome { earned, declined, unavailable }

/// Whether a new assistant conversation may start.
///
/// Asked once, at the first billable send of a NEW conversation, after
/// consent. Never asked for a resumed conversation, a follow-up, a send that
/// carries only video (nothing is sent, so nothing is billed) or a Premium
/// user -- the caller decides which sends are "first", this decides whether
/// the ad was earned.
///
/// The decision half of the rewarded-ad gate, deliberately free of any AdMob
/// type so it can be tested: `google_mobile_ads` talks over platform channels
/// that have no handler under `flutter_tester`. [confirm] shows the opt-in
/// prompt, [showAd] plays the ad; `rewarded_describe_ad.dart` supplies the
/// real ones.
///
/// The two failure modes split, and the split is the point:
///
///   * The user abandons the ad -> NOT earned. They chose not to watch.
///   * The ad could not be served -> proceeds ANYWAY. No-fill, an outage or a
///     flaky network is not the user's doing, and letting it block the feature
///     would mean an AdMob hiccup silently disables something the user has
///     already consented to and that costs money whether or not an ad ran.
///
/// Erring toward the user costs an impression. Erring the other way makes the
/// feature look broken, which costs the install.
Future<bool> earnOneConversation({
  required bool premium,
  required Future<bool> Function() confirm,
  required Future<RewardedOutcome> Function() showAd,
}) async {
  // Checked first, so premium never sees the prompt -- let alone the ad.
  // Paying to remove ads and then being asked to watch one is the single
  // fastest way to earn a refund request.
  if (premium) return true;

  // The opt-in is not politeness, it is the policy: a rewarded ad has to be
  // offered and accepted, never sprung on a tap.
  if (!await confirm()) return false;

  return switch (await showAd()) {
    RewardedOutcome.earned => true,
    RewardedOutcome.declined => false,
    RewardedOutcome.unavailable => true,
  };
}
