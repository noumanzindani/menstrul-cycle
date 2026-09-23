import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/services/ad_config.dart';

/// The rewarded unit has to be a REAL id, not the `0000...` placeholder the
/// prod constants ship with. A placeholder id does not fail loudly -- it just
/// never fills, which looks exactly like "no ad available" and would silently
/// hand every user a free conversation forever (see `earnOneConversation`'s
/// fail-open).
void main() {
  const googleTestRewarded = {
    'ca-app-pub-3940256099942544/5224354917', // Android
    'ca-app-pub-3940256099942544/1712485313', // iOS
  };

  test('ships Google\'s official rewarded test unit while useTestAds is on',
      () {
    expect(AdConfig.useTestAds, isTrue,
        reason: 'flip this only alongside real _prod ids');
    expect(googleTestRewarded, contains(AdConfig.rewardedUnitId));
  });

  test('the rewarded unit is not the placeholder', () {
    expect(AdConfig.rewardedUnitId, isNot(contains('0000000000')));
  });
}
