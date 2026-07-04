import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider provider;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = SettingsProvider(SettingsRepository(db));
    await provider.load();
  });
  tearDown(() => db.close());

  test('mode defaults to track', () {
    expect(provider.mode, TrackingMode.track);
  });

  test('setMode round-trips through the settings row', () async {
    await provider.setMode(TrackingMode.conceive);
    expect(provider.mode, TrackingMode.conceive);
  });
}
