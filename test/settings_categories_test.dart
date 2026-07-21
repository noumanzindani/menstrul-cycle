import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

/// The category preference is stored as a JSON array in one nullable column.
/// The distinction that matters: NULL means "never customised" (use defaults),
/// EMPTY means "turned everything off" (a real choice). Conflating them would
/// resurrect every category the user just disabled.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  test('a null column falls back to the registry defaults', () {
    expect(settings.enabledCategories, defaultEnabledCategoryIds());
    expect(settings.enabledCategories, isNot(contains(kCatUrine)));
    expect(settings.enabledCategories, contains(kCatPhysicalSymptoms));
  });

  test('enabling a category round-trips through the database', () async {
    await settings.setCategoryEnabled(kCatUrine, true);
    expect(settings.enabledCategories, contains(kCatUrine));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, contains(kCatUrine));
  });

  test('disabling a default-on category round-trips', () async {
    await settings.setCategoryEnabled(kCatLifestyle, false);
    expect(settings.enabledCategories, isNot(contains(kCatLifestyle)));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, isNot(contains(kCatLifestyle)));
  });

  test('turning everything off persists as empty, NOT as reset-to-defaults',
      () async {
    for (final c in kTrackingCategories) {
      await settings.setCategoryEnabled(c.id, false);
    }
    expect(settings.enabledCategories, isEmpty);

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, isEmpty,
        reason: 'empty must not be treated as unset');
  });

  test('an unknown id stored by a future version is ignored, not crashed on',
      () async {
    await settings.update(const AppSettingsCompanion(
      trackingCategories: Value('["urine","not_a_real_category"]'),
    ));
    await settings.load();
    expect(settings.enabledCategories, contains(kCatUrine));
    expect(settings.enabledCategories, isNot(contains('not_a_real_category')));
  });

  test('malformed JSON falls back to defaults instead of throwing', () async {
    await settings.update(
        const AppSettingsCompanion(trackingCategories: Value('{not json')));
    await settings.load();
    expect(settings.enabledCategories, defaultEnabledCategoryIds());
  });
}
