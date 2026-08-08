import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  test('startPregnancy persists mode + date; endPregnancy clears them', () async {
    await settings.startPregnancy(DateTime(2026, 2, 1));
    expect(settings.isPregnant, isTrue);
    expect(settings.mode, TrackingMode.pregnancy);
    expect(settings.pregnancyStartDate, DateTime(2026, 2, 1));

    await settings.endPregnancy();
    expect(settings.isPregnant, isFalse);
    expect(settings.mode, TrackingMode.track);
    expect(settings.pregnancyStartDate, isNull);
  });

  testWidgets('Home shows the pregnancy view and no ads when pregnant',
      (tester) async {
    await settings.startPregnancy(
        DateTime.now().subtract(const Duration(days: 7 * 20)));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        // Pregnancy home carries a running session through rather than
        // orphaning it. No fixture here starts one.
        ChangeNotifierProvider<ProductSessionProvider>(
          create: (_) => ProductSessionProvider(
              ProductSessionRepository(ReminderRepository(db))),
        ),
        Provider<PredictionResult>.value(
            value: PredictionService.predict(const [])),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Trimester'), findsOneWidget);
    // No ads on the pregnancy surface (loss-safe rule).
    expect(find.byType(AdBanner), findsNothing);
  });
}
