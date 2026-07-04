import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';

void main() {
  testWidgets('First run shows onboarding', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(LunaTrackApp(database: db));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to LunaTrack'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // Not yet in the main app.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('After onboarding, app boots to Home', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Simulate a returning user who already finished onboarding.
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0)))
        .write(const AppSettingsCompanion(onboardingComplete: Value(true)));

    await tester.pumpWidget(LunaTrackApp(database: db));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });
}
