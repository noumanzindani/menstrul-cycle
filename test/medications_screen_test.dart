import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/medication.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/screens/medications/medications_screen.dart';

/// End-to-end: the Medications screen adds a medication (without a reminder, so
/// no OS notification plugin is touched) and shows it in the list.
void main() {
  late AppDatabase db;
  late MedicationProvider meds;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    meds = MedicationProvider(MedicationRepository(db));
    await meds.load();
  });
  tearDown(() => db.close());

  Widget wrap(Widget child) => ChangeNotifierProvider<MedicationProvider>.value(
        value: meds,
        child: MaterialApp(home: child),
      );

  testWidgets('adding a medication persists it and lists it', (tester) async {
    await tester.pumpWidget(wrap(const MedicationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No medications yet'), findsOneWidget);

    await tester.tap(find.text('Add')); // FAB
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Iron');
    await tester.tap(find.text('Supplement / vitamin')); // type chip
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Persisted with the chosen type, and shown as a card.
    final saved = meds.items.single;
    expect(saved.name, 'Iron');
    expect(saved.type, MedicationType.supplement);
    expect(saved.enabled, isTrue);
    expect(find.text('Iron'), findsOneWidget);
  });
}
