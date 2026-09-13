import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// INTEGRATION: the doctor PDF's profile header has to be reachable from the
/// running app, not just from `PdfReportService.build`'s own unit tests.
///
/// `PdfReportService.build` grew four optional named profile params. Optional
/// named params fail silently when a call site forgets them — the report is
/// still produced, it is simply missing the block, and every service-level
/// test keeps passing. This file pins the ONE call site (the Insights app-bar
/// export) by driving the real button and inspecting the bytes that actually
/// reach `Printing.sharePdf`.
///
/// Assertions are by output SIZE, matching the convention in
/// `pdf_report_service_test.dart` and `weight_trend_service_test.dart`: the
/// `pdf` package compresses its text streams, so a byte-substring search finds
/// nothing even for text that IS present.
void main() {
  late AppDatabase db;
  late LogProvider logs;
  late SettingsProvider settings;

  /// Bytes handed to `Printing.sharePdf` by the most recent export.
  Uint8List? shared;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    // Two period runs 28 days apart -> at least one complete cycle, so
    // `stats.hasData` is true and the export action is rendered at all.
    for (final start in [DateTime(2026, 1, 1), DateTime(2026, 1, 29)]) {
      for (var i = 0; i < 3; i++) {
        await repo.upsert(
          date: start.add(Duration(days: i)),
          flow: FlowIntensity.medium,
          symptomsJson: '{}',
        );
      }
    }
    await logs.load();
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();

    shared = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('net.nfet.printing'),
      (call) async {
        if (call.method == 'sharePdf') {
          shared = call.arguments['doc'] as Uint8List;
          return 1;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('net.nfet.printing'), null);
    await db.close();
  });

  /// Pumps Insights, taps the app-bar export action and returns the number of
  /// bytes that reached the share sheet.
  Future<int> exportedBytes(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<PredictionResult>.value(
          value: PredictionService.predict(logs.cycles),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InsightsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    shared = null;
    await tester.tap(find.byTooltip('Export PDF for your doctor'));
    await tester.pumpAndSettle();

    final bytes = shared;
    expect(bytes, isNotNull,
        reason: 'the export never reached Printing.sharePdf');
    return bytes!.length;
  }

  testWidgets('the export sends every profile answer to the report',
      (tester) async {
    final baseline = await exportedBytes(tester);

    // Each field is wired independently, so a call site that forgot any ONE of
    // the four is caught. A single combined assertion would pass on 1-of-4.
    await settings.setDateOfBirth(DateTime(1995, 6, 15));
    expect(await exportedBytes(tester), greaterThan(baseline),
        reason: 'dateOfBirth never reached PdfReportService.build');
    await settings.setDateOfBirth(null);

    await settings.setHeightCm(170);
    expect(await exportedBytes(tester), greaterThan(baseline),
        reason: 'heightCm never reached PdfReportService.build');
    await settings.setHeightCm(null);

    await settings.setProfileWeightKg(62);
    expect(await exportedBytes(tester), greaterThan(baseline),
        reason: 'profileWeightKg never reached PdfReportService.build');
    await settings.setProfileWeightKg(null);

    await settings.setMenarcheAge(13);
    expect(await exportedBytes(tester), greaterThan(baseline),
        reason: 'menarcheAge never reached PdfReportService.build');
  });

  testWidgets('a user who skipped the profile exports the report unchanged',
      (tester) async {
    // The negative half, and what keeps the assertions above non-vacuous: the
    // size probe only means something if an unanswered profile adds nothing.
    final baseline = await exportedBytes(tester);

    await settings.setDateOfBirth(null);
    await settings.setHeightCm(null);
    await settings.setProfileWeightKg(null);
    await settings.setMenarcheAge(null);

    expect(await exportedBytes(tester), baseline);
  });
}
