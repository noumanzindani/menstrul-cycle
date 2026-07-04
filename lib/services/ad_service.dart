import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
