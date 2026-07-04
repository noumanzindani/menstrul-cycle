import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'ad_config.dart';

/// Thin wrapper over in_app_purchase for a SINGLE non-consumable product
/// (Premium / remove ads). No server receipt validation — for a remove-ads
/// unlock the stakes are low, so we trust the store client.
class IapService {
  IapService._();
  static final instance = IapService._();

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  bool _available = false;
  bool get isStoreAvailable => _available;

  /// Localized price string for the paywall, e.g. "$4.99". Null if not loaded.
  String? get price => _product?.price;

  /// Begin listening to the purchase stream. [onPremiumUnlocked] fires whenever
  /// a valid purchase/restore for the premium product is delivered.
  Future<void> init(VoidCallback onPremiumUnlocked) async {
    _available = await _iap.isAvailable();
    if (!_available) return;

    _sub = _iap.purchaseStream.listen(
      (purchases) => _onPurchases(purchases, onPremiumUnlocked),
      onError: (e) => debugPrint('Purchase stream error: $e'),
    );

    final response =
        await _iap.queryProductDetails({kPremiumProductId});
    if (response.productDetails.isNotEmpty) {
      _product = response.productDetails.first;
    }
  }

  Future<void> _onPurchases(
    List<PurchaseDetails> purchases,
    VoidCallback onPremiumUnlocked,
  ) async {
    for (final p in purchases) {
      if (p.productID != kPremiumProductId) continue;
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        onPremiumUnlocked();
      }
      // Must always complete, or the store keeps redelivering it.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  /// Kicks off the buy flow. Result arrives asynchronously via the stream.
  Future<bool> buyPremium() async {
    if (!_available || _product == null) return false;
    final param = PurchaseParam(productDetails: _product!);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Ask the store to redeliver past purchases (result arrives via the stream).
  Future<void> restore() async {
    if (!_available) return;
    await _iap.restorePurchases();
  }

  void dispose() => _sub?.cancel();
}
