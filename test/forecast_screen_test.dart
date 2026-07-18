import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/forecast/forecast_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:drift/native.dart';

/// Each forecast card already surfaces the fertile-start date; it should also
/// surface the PMS window, matching the other predictions this list shows.
void main() {
  testWidgets('each period card shows a PMS line', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final period = PredictedPeriod(
      start: DateTime(2026, 7, 30),
      end: DateTime(2026, 8, 3),
      ovulation: DateTime(2026, 7, 16),
      fertileStart: DateTime(2026, 7, 11),
      fertileEnd: DateTime(2026, 7, 17),
      pmsStart: DateTime(2026, 7, 25),
      pmsEnd: DateTime(2026, 7, 29),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<List<PredictedPeriod>>.value(value: [period]),
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(SettingsRepository(db))..load(),
          ),
          ChangeNotifierProvider(
            create: (_) => PremiumProvider(SettingsRepository(db)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ForecastScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('PMS'), findsOneWidget);
  });
}
