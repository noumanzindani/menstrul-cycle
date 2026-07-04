import 'dart:io';

import 'package:flutter/foundation.dart';

/// Central place for AdMob unit IDs. Ships with GOOGLE'S OFFICIAL TEST IDs so
/// the app runs and shows (test) ads with no account. Before release, set
/// [useTestAds] to false and drop your real IDs into the `_prod*` constants.
///
/// Real IDs come from https://apps.admob.com after creating the app + ad units.
class AdConfig {
  AdConfig._();

  /// FLIP TO false FOR RELEASE (after filling in the _prod* IDs below).
  static const bool useTestAds = true;

  // --- Google official test unit IDs (safe to ship for testing) ---
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  // --- TODO: your real IDs (used only when useTestAds == false) ---
  static const _prodBannerAndroid = 'ca-app-pub-0000000000000000/0000000000';
  static const _prodBannerIos = 'ca-app-pub-0000000000000000/0000000000';
  static const _prodInterstitialAndroid =
      'ca-app-pub-0000000000000000/0000000000';
  static const _prodInterstitialIos = 'ca-app-pub-0000000000000000/0000000000';

  static bool get _android => !kIsWeb && Platform.isAndroid;

  static String get bannerUnitId {
    if (useTestAds) return _android ? _testBannerAndroid : _testBannerIos;
    return _android ? _prodBannerAndroid : _prodBannerIos;
  }

  static String get interstitialUnitId {
    if (useTestAds) {
      return _android ? _testInterstitialAndroid : _testInterstitialIos;
    }
    return _android ? _prodInterstitialAndroid : _prodInterstitialIos;
  }
}

/// One-time non-consumable product that removes ads + unlocks Premium features.
/// This ID must match the product you create in Play Console / App Store Connect.
const String kPremiumProductId = 'lunatrack_premium';
