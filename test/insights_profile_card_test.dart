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

/// Insights surfaces the two figures DERIVED from the profile answers:
/// gynaecological age (years since the first period) and the body-index
/// readout. Neither is stored — both are recomputed from the four raw fields
/// every build, so an edit in Settings can never leave a stale copy behind.
///
/// The two halves degrade independently: one pair of answers missing must
/// never hide the other value, and a user who skipped the profile entirely
/// sees the Insights screen exactly as it was before this card existed.
void main() {
  late AppDatabase db;
  late LogProvider logs;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    // Two period runs 28 days apart -> at least one cycle, so `stats.hasData`
    // is true and the screen renders its section list rather than the empty
    // state. Nothing about the profile card depends on these logs.
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
  });

  tearDown(() => db.close());

  /// A birthday of 1 January exactly [years] ago: it has always already passed
  /// whatever day the suite runs on, so the derived age is [years] every time.
  DateTime birthdayFor(int years) =>
      DateTime(DateTime.now().year - years, 1, 1);

  Future<void> pump(WidgetTester tester) async {
    // A tall, phone-width surface so the whole section list is laid out at
    // once. Without it the ListView is lazy and "not found" would only ever
    // mean "below the fold", which would make every absence assertion vacuous.
    tester.view.physicalSize = const Size(400, 2400);
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
        home: const InsightsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final card = find.text('From your profile');

  testWidgets('shows both derived figures when the whole profile is answered',
      (tester) async {
    await settings.setDateOfBirth(birthdayFor(30));
    await settings.setMenarcheAge(13);
    await settings.setHeightCm(170);
    await settings.setProfileWeightKg(70);

    await pump(tester);

    expect(card, findsOneWidget);
    // 30 years old today, first period at 13 -> 17 years since menarche.
    expect(find.textContaining('Gynaecological age'), findsOneWidget);
    expect(find.textContaining('17 years'), findsOneWidget);
    // 70kg / 1.70m^2 = 24.22 -> rounded to one decimal, labelled from the
    // rounded figure. The exact string must come out of BmiService; this
    // asserts the screen renders it verbatim rather than composing its own.
    expect(find.text('BMI 24.2 - normal range'), findsOneWidget);
  });

  testWidgets('the card is absent when no profile answers exist',
      (tester) async {
    await pump(tester);

    expect(card, findsNothing);
    expect(find.textContaining('Gynaecological age'), findsNothing);
    expect(find.textContaining('BMI'), findsNothing);
    // ...and the rest of the screen is untouched, so the absence above is a
    // real gate rather than a screen that failed to build at all.
    expect(find.text('Cycles tracked'), findsOneWidget);
    expect(find.text('Cycle history'), findsOneWidget);
  });

  testWidgets('gynaecological age stands alone when height and weight are '
      'unanswered', (tester) async {
    await settings.setDateOfBirth(birthdayFor(25));
    await settings.setMenarcheAge(12);

    await pump(tester);

    expect(card, findsOneWidget);
    expect(find.textContaining('13 years'), findsOneWidget);
    expect(find.textContaining('BMI'), findsNothing);
  });

  testWidgets('the index readout stands alone when the date of birth and '
      'menarche age are unanswered', (tester) async {
    await settings.setHeightCm(160);
    await settings.setProfileWeightKg(45);

    await pump(tester);

    expect(card, findsOneWidget);
    // 45kg / 1.60m^2 = 17.58 -> below the first band floor.
    expect(find.text('BMI 17.6 - underweight'), findsOneWidget);
    expect(find.textContaining('Gynaecological age'), findsNothing);
  });

  testWidgets('a date of birth with no menarche age shows neither figure',
      (tester) async {
    await settings.setDateOfBirth(birthdayFor(30));

    await pump(tester);

    expect(card, findsNothing);
  });

  testWidgets('a height with no weight shows neither figure', (tester) async {
    await settings.setHeightCm(170);

    await pump(tester);

    expect(card, findsNothing);
  });

  group('gynaecologicalAgeYears', () {
    test('subtracts the menarche age from the age reached today', () {
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2000, 6, 1),
          menarcheAge: 12,
          asOf: DateTime(2026, 6, 1),
        ),
        26 - 12,
      );
    });

    test('a birthday still to come this year has not been reached yet', () {
      // 31 December 2000 -> on 1 June 2026 the user is 25, not 26.
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2000, 12, 31),
          menarcheAge: 12,
          asOf: DateTime(2026, 6, 1),
        ),
        25 - 12,
      );
    });

    test('menarche in the current year reads as zero, not as no answer', () {
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2012, 3, 4),
          menarcheAge: 14,
          asOf: DateTime(2026, 6, 1),
        ),
        0,
      );
    });

    test('refuses a menarche age the user has not reached yet', () {
      // A typo, not a negative gynaecological age: show nothing.
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2015, 1, 1),
          menarcheAge: 30,
          asOf: DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });

    test('refuses a date of birth in the future', () {
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2030, 1, 1),
          menarcheAge: 0,
          asOf: DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });

    test('either field unanswered means no figure', () {
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: null,
          menarcheAge: 12,
          asOf: DateTime(2026, 6, 1),
        ),
        isNull,
      );
      expect(
        gynaecologicalAgeYears(
          dateOfBirth: DateTime(2000, 1, 1),
          menarcheAge: null,
          asOf: DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });
  });
}
