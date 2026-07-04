import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../db/database.dart';
import '../services/iap_service.dart';

/// Single source of truth for premium (ads-removed) status. The flag is
/// persisted in the settings row and unlocked via [IapService]. Ad widgets and
/// feature gates watch this.
class PremiumProvider extends ChangeNotifier {
  PremiumProvider(this._settings);
  final SettingsRepository _settings;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  String? get price => IapService.instance.price;
  bool get storeAvailable => IapService.instance.isStoreAvailable;

  Future<void> load() async {
    final s = await _settings.get();
    _isPremium = s.premium;
    notifyListeners();
    // Start the store; unlock persists premium when a purchase/restore arrives.
    await IapService.instance.init(_unlock);
  }

  Future<void> _unlock() async {
    if (_isPremium) return;
    _isPremium = true;
    await _settings.update(const AppSettingsCompanion(premium: Value(true)));
    notifyListeners();
  }

  Future<bool> buy() => IapService.instance.buyPremium();
  Future<void> restore() => IapService.instance.restore();
}
