import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';

/// The pattern cards from `CyclePatternsService`: each appears once there is
/// enough data, stays hidden below it, and fertility signs appear in Conceive
/// mode only.
void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  late SettingsProvider settings;
  final day0 = DateTime(2026, 1, 1);
  DateTime d(int i) => DateTime(day0.year, day0.month, day0.day + i);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  const flows = [
    FlowIntensity.light,
    FlowIntensity.heavy,
    FlowIntensity.medium,
    FlowIntensity.light,
    FlowIntensity.spotting,
  ];

  /// Periods at days 0, 28, 56, 84 and 112 → four complete 28-day cycles.
  Future<void> seedRich() async {
    final tags = <int, Map<String, Object>>{};
    final opk = <int, String>{};
    void tag(int day, String k, Object v) => (tags[day] ??= {})[k] = v;
    for (var c = 0; c < 4; c++) {
      final s = c * 28;
      for (var i = 0; i < 5; i++) {
        tag(s + i, 'pain', i == 1 ? 8 : 4);
        tag(s + i, 'energy', 2);
      }
      for (final i in [7, 8, 9]) {
        tag(s + i, 'energy', 4);
      }
      tag(s + 26, 'headache', true); // 2 days before the next period
      tag(s + 27, 'headache', true);
      opk[s + 13] = 'positive';
    }
    // Alcohol on 6 days, cramps on 5 of them; almost never otherwise.
    for (var i = 0; i < 6; i++) {
      tag(40 + i * 3, 'habit_alcohol', true);
      if (i < 5) tag(40 + i * 3, 'cramps', true);
    }
    final all = <int>{
      ...tags.keys,
      ...opk.keys,
      for (var c = 0; c < 5; c++)
        for (var i = 0; i < 5; i++) c * 28 + i,
    };
    for (final day in all) {
      final inPeriod = day % 28 < 5 && day <= 116;
      await repo.upsert(
        date: d(day),
        flow: inPeriod ? flows[day % 28] : null,
        symptomsJson: jsonEncode(tags[day] ?? {}),
        opk: opk[day],
      );
    }
    await logs.load();
  }

  Future<void> seedMinimal() async {
    for (final start in [0, 28]) {
      for (var i = 0; i < 3; i++) {
        await repo.upsert(
            date: d(start + i), flow: FlowIntensity.medium, symptomsJson: '{}');
      }
    }
    await logs.load();
  }

  Future<void> pump(WidgetTester tester, {double width = 400}) async {
    // Tall enough that every card is laid out, so absences are real.
    tester.view.physicalSize = Size(width, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const InsightsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const titles = [
    'Phase by phase',
    'Before your period',
    'Your period, day by day',
    'Pain over time',
    'Logged together',
  ];

  testWidgets('with enough data, every pattern card appears', (tester) async {
    await seedRich();
    await pump(tester);
    for (final t in titles) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('Headache usually starts about 2 days'),
        findsOneWidget);
    expect(find.textContaining('heaviest on day 2'), findsOneWidget);
    expect(find.textContaining('cramps on 5 of 6 days you logged alcohol'),
        findsOneWidget);
  });

  testWidgets('shows how much data the insights rest on', (tester) async {
    await seedRich();
    await pump(tester);
    expect(find.textContaining('Based on 4 complete cycles'), findsOneWidget);
  });

  testWidgets('with thin data, none of the pattern cards appear',
      (tester) async {
    await seedMinimal();
    await pump(tester);
    for (final t in titles) {
      expect(find.text(t), findsNothing, reason: t);
    }
  });

  testWidgets('fertility signs are hidden outside Conceive mode',
      (tester) async {
    await seedRich();
    await pump(tester);
    expect(find.text('Fertility signs'), findsNothing);
  });

  testWidgets('fertility signs appear in Conceive mode', (tester) async {
    await seedRich();
    await settings.setMode(TrackingMode.conceive);
    await pump(tester);
    expect(find.text('Fertility signs'), findsOneWidget);
    expect(find.textContaining('cycle day 14'), findsOneWidget);
  });

  testWidgets('the lifestyle card says it is not cause and effect',
      (tester) async {
    await seedRich();
    await pump(tester);
    expect(find.textContaining('not necessarily cause and effect'),
        findsOneWidget);
  });

  testWidgets('GUARDRAIL: still no ad banner', (tester) async {
    await seedRich();
    await pump(tester);
    expect(find.byType(AdBanner), findsNothing);
  });

  testWidgets('every card fits a 360dp phone in the real theme',
      (tester) async {
    await seedRich();
    await settings.setMode(TrackingMode.conceive);
    await pump(tester, width: 360);
    expect(tester.takeException(), isNull,
        reason: 'a RenderFlex overflow is debug-only on a device');
    expect(find.text('Phase by phase'), findsOneWidget);
  });
}
