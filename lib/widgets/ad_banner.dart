import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../providers/premium_provider.dart';
import '../services/ad_config.dart';
import '../services/ad_service.dart';

/// An adaptive anchored banner. Renders NOTHING for premium users, before
/// consent, or while loading — so it never reserves empty space.
///
/// COUNCIL RULE: only place this on Home, Calendar, and Settings. Never on the
/// day-log or insights screens.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final premium = context.watch<PremiumProvider>().isPremium;
    if (premium) {
      _dispose();
    } else if (_ad == null && AdService.instance.canRequestAds) {
      _load();
    }
  }

  void _load() {
    final banner = BannerAd(
      size: AdSize.banner,
      adUnitId: AdConfig.bannerUnitId,
      request: AdService.request,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    );
    _ad = banner;
    banner.load();
  }

  void _dispose() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumProvider>().isPremium;
    if (premium || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
