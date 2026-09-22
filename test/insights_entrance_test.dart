import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';
import 'package:menstrul_track/widgets/disclaimer_banner.dart';
import 'package:menstrul_track/widgets/entrance.dart';

/// Insights staggers its section cards in — with two deliberate exemptions.
///
/// The [DisclaimerBanner] one is the whole reason this file exists. It is
/// required on every surface carrying estimates or a fertility observation,
/// which is exactly what the cards above it are, so a disclaimer that fades in
/// AFTER the claims it qualifies is the one piece of motion on this screen that
/// would be actively wrong. The spacer exemption is cheaper but still load
/// bearing: this list interleaves `SizedBox`es between cards, and numbering
/// them would spend the six stagger slots on gaps.
void main() {
  late AppDatabase db;
  late LogProvider logs;
  late DailyLogRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
  });
  tearDown(() => db.close());

  Widget wrap() => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InsightsScreen(),
        ),
      );

  /// Four period runs ~28 days apart → three complete cycles, which is enough
  /// for the screen to leave its empty state and render real sections.
  Future<void> seed() async {
    for (final m in [1, 2, 3, 4]) {
      for (final d in [1, 2, 3]) {
        await repo.upsert(
          date: DateTime(2026, m, d),
          flow: FlowIntensity.medium,
          symptomsJson: '{}',
        );
      }
    }
    await logs.load();
  }

  testWidgets('the section cards are staggered', (tester) async {
    await seed();
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(EntranceGroup), findsOneWidget);
    expect(find.byType(EntranceItem), findsWidgets);
  });

  testWidgets('the disclaimer is NOT staggered: it never fades in after the '
      'estimates it qualifies', (tester) async {
    await seed();
    await tester.pumpWidget(wrap());
    await tester.pump();

    // Read off the children list rather than the rendered tree: the banner
    // sits at the bottom of a long lazy ListView and is not built until it is
    // scrolled to, so `find.byType` would report nothing for the wrong reason.
    final list = tester.widget<ListView>(find.byType(ListView));
    final children = (list.childrenDelegate as SliverChildListDelegate).children;

    expect(
      children.whereType<DisclaimerBanner>(),
      hasLength(1),
      reason: 'the disclaimer must be a DIRECT child -- unwrapped, so it '
          'arrives with the screen rather than after it',
    );
    expect(
      children.whereType<EntranceItem>().map((e) => e.child),
      everyElement(isNot(isA<DisclaimerBanner>())),
    );
  });

  testWidgets('spacers do not consume stagger slots', (tester) async {
    await seed();
    await tester.pumpWidget(wrap());
    await tester.pump();

    // Every SizedBox that is a DIRECT child of the staggered list is passed
    // through untouched. Checking the list's own children rather than every
    // SizedBox on screen, since the cards contain plenty of their own.
    final list = tester.widget<ListView>(find.byType(ListView));
    final children = (list.childrenDelegate as SliverChildListDelegate).children;
    for (final child in children) {
      if (child is EntranceItem) {
        expect(child.child, isNot(isA<SizedBox>()));
        expect(child.child, isNot(isA<DisclaimerBanner>()));
      }
    }

    // ...and the indices really are dense: no gaps where a spacer sat.
    final indices = children.whereType<EntranceItem>().map((e) => e.index);
    expect(indices, List.generate(indices.length, (i) => i));
  });
}
