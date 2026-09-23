import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/screens/media/rewarded_describe_prompt.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The rewarded ad's opt-in. Since the assistant, one ad starts a whole
/// conversation, so the prompt must offer exactly that and nothing more.
void main() {
  bool? answer;

  Future<void> open(WidgetTester tester) async {
    answer = null;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answer = await showRewardedDescribePrompt(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers an ad for a conversation, not for one description',
      (tester) async {
    await open(tester);

    expect(find.text('Watch an ad to start a conversation?'), findsOneWidget);
    expect(find.text('Watch an ad to describe this?'), findsNothing);
    expect(find.text('Watch ad'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Watch ad agrees', (tester) async {
    await open(tester);
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('Not now declines', (tester) async {
    await open(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
