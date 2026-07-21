import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/tracking_categories_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    // A lazy ListView only builds what fits the viewport, and 13 switches do
    // not fit the default 800x600 surface. Give the test a tall window rather
    // than weakening "lists EVERY category" into a partial assertion.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrackingCategoriesScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every category and reflects the defaults',
      (tester) async {
    await pump(tester);
    expect(
        find.byType(SwitchListTile), findsNWidgets(kTrackingCategories.length));

    SwitchListTile tileFor(String label) =>
        tester.widget<SwitchListTile>(find.ancestor(
          of: find.text(label),
          matching: find.byType(SwitchListTile),
        ));

    expect(tileFor('Urine').value, isFalse);
    expect(tileFor('Physical symptoms').value, isTrue);
  });

  testWidgets('toggling a switch persists the choice', (tester) async {
    await pump(tester);

    await tester.dragUntilVisible(
        find.text('Urine'), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urine'));
    await tester.pumpAndSettle();

    expect(settings.enabledCategories, contains(kCatUrine));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, contains(kCatUrine));
  });

  // The prefixed groups are stripped by decodeSymptoms, so they reach neither
  // Insights nor the doctor PDF. Promising otherwise would be a false claim
  // about where the user's health data goes.
  testWidgets('does not promise Insights or PDF visibility', (tester) async {
    await pump(tester);
    expect(find.textContaining('Insights'), findsNothing);
    expect(find.textContaining('PDF'), findsNothing);
    expect(find.textContaining('doctor'), findsNothing);
  });
}
