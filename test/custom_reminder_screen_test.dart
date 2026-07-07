import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/reminder_provider.dart';
import 'package:menstrul_track/screens/reminders/reminders_screen.dart';

/// The Reminders screen lists the user's custom reminders below the three smart
/// ones. (Seeded via the repo so no notification plugin is touched.)
void main() {
  late AppDatabase db;
  late ReminderProvider provider;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('lists a custom reminder', (tester) async {
    final repo = ReminderRepository(db);
    await repo.addCustom(title: 'Drink water', hour: 8, minute: 0);
    provider = ReminderProvider(repo);
    await provider.load();

    await tester.pumpWidget(ChangeNotifierProvider<ReminderProvider>.value(
      value: provider,
      child: const MaterialApp(home: RemindersScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Drink water'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Custom reminders'), findsOneWidget);
  });
}
