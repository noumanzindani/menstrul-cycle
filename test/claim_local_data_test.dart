import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/auth/claim_local_data_sheet.dart';

void main() {
  Future<bool?> show(WidgetTester tester, int count) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showClaimLocalDataSheet(context,
                    dayCount: count);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('states how many days are on the device', (tester) async {
    await show(tester, 42);
    expect(find.textContaining('42 days'), findsOneWidget);
  });

  testWidgets('adding to the account returns true', (tester) async {
    await show(tester, 3);
    await tester.tap(find.byKey(const Key('claim.upload')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsNothing);
  });

  testWidgets('the Android system back button does not dismiss the sheet',
      (tester) async {
    await show(tester, 3);
    expect(find.byKey(const Key('claim.upload')), findsOneWidget);

    // `isDismissible: false` / `enableDrag: false` block the barrier tap and
    // the drag, but NOT the system back button, which pops the route and
    // returns null. A null result must never be read as a decline (see
    // `AppGate._maybePromptClaim`), and `PopScope(canPop: false)` stops it
    // happening in the first place.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsOneWidget);
  });

  testWidgets('keeping data on the device offers a non-destructive choice',
      (tester) async {
    await show(tester, 3);

    // The decline path must be clearly non-destructive: it never deletes.
    expect(find.byKey(const Key('claim.keepLocal')), findsOneWidget);
    expect(find.textContaining('stay on this device'), findsOneWidget);
  });
}
