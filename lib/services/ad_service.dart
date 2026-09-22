import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'rewarded_describe_gate.dart';
import 'ad_config.dart';

/// Owns AdMob initialization, UMP consent, and interstitial loading.
///
/// Council constraints enforced here:
/// - Ads are always NON-PERSONALIZED (sidesteps COPPA/GDPR-K for teen users).
/// - UMP consent is gathered before requesting ads.
/// - Banner placement (Home/Calendar/Settings only, never log/insights) is
///   enforced by WHERE [AdBanner] is placed, not here.
class AdService {
  AdService._();
  static final instance = AdService._();

  bool _initialized = false;
  bool _canRequestAds = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  /// Always request non-personalized ads.
  static AdRequest get request => const AdRequest(nonPersonalizedAds: true);

  bool get canRequestAds => _canRequestAds;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    await _gatherConsent();
  }

  Future<void> _gatherConsent() async {
    try {
      final params = ConsentRequestParameters();
      final info = ConsentInformation.instance;
      // Wrap the callback-based API in a Future.
      await _requestConsentUpdate(info, params);
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form error: ${error.message}');
      });
      _canRequestAds = await info.canRequestAds();
    } catch (e) {
      // If consent flow fails, fall back to non-personalized ads being allowed
      // only if the platform says so; default to true so the app still earns
      // with NON-personalized ads (the only kind we ever request).
      debugPrint('Consent flow error: $e');
      _canRequestAds = true;
    }
  }

  Future<void> _requestConsentUpdate(
    ConsentInformation info,
    ConsentRequestParameters params,
  ) {
    return Future<void>(() {
      info.requestConsentInfoUpdate(
        params,
        () {}, // success — canRequestAds() is read afterwards
        (error) => debugPrint('Consent update failed: ${error.message}'),
      );
    });
  }

  /// Preloads the rewarded unit so [showRewarded] can play instantly. No-op
  /// for premium users or before consent, exactly like the interstitial.
  Future<void> preloadRewarded({required bool premium}) async {
    if (premium || !_canRequestAds || _rewarded != null) return;
    await RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Plays the rewarded ad and reports how it ended.
  ///
  /// Returns [RewardedOutcome.unavailable] when there was nothing to show --
  /// no fill, a failed load, an outage. The caller MUST distinguish that from
  /// [RewardedOutcome.declined] (the user walked away mid-ad); see
  /// `earnOneDescribe`, which lets the first through and refuses the second.
  /// Collapsing them is how an AdMob outage turns into a feature that looks
  /// broken.
  ///
  /// Deliberately thin: everything decidable lives in `earnOneDescribe`,
  /// because nothing in this file can be exercised under `flutter_tester` --
  /// `google_mobile_ads` talks over platform channels with no test handler.
  Future<RewardedOutcome> showRewarded({required bool premium}) async {
    if (premium) return RewardedOutcome.earned;
    final ad = _rewarded;
    if (ad == null) {
      // Nothing preloaded. Kick off a load for NEXT time and let this one by.
      unawaited(preloadRewarded(premium: premium));
      return RewardedOutcome.unavailable;
    }
    _rewarded = null;

    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadRewarded(premium: premium);
      },
      onAdFailedToShowFullScreenContent: (ad, _) => ad.dispose(),
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    // `show` completes once the ad is dismissed, so `earned` is settled here.
    return earned ? RewardedOutcome.earned : RewardedOutcome.declined;
  }

  /// Preloads an interstitial so it can be shown instantly later. No-op for
  /// premium users or before consent.
  Future<void> preloadInterstitial({required bool premium}) async {
    if (premium || !_canRequestAds || _interstitial != null) return;
    await InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Shows the preloaded interstitial if available. Caller is responsible for
  /// NOT calling this during a logging flow (council rule).
  Future<void> showInterstitial({required bool premium}) async {
    if (premium) return;
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadInterstitial(premium: premium);
      },
      onAdFailedToShowFullScreenContent: (ad, _) => ad.dispose(),
    );
    await ad.show();
  }
}
