import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/media/analysis_result_sheet.dart';
import 'package:menstrul_track/services/media_analysis.dart';

/// The conversation UI. No service, no network — [AnalysisResultSheet.onAsk] is
/// injected, which is the whole reason this widget is testable at all.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> ask(WidgetTester tester, String question) async {
    await tester.enterText(
      find.byKey(const Key('analysis-question-field')),
      question,
    );
    await tester.tap(find.byKey(const Key('analysis-ask-button')));
  }

  testWidgets('opens showing the description', (tester) async {
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) async => const AnalysisSheetReply('unused'),
        ),
      ),
    );
    expect(find.text('A pink diamond pattern.'), findsOneWidget);
  });

  testWidgets('keeps the earlier turns on screen', (tester) async {
    // The single-answer version replaced the text, so asking a follow-up erased
    // the description it was about. A conversation you cannot scroll back
    // through is not a conversation.
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (q) async => AnalysisSheetReply('Answering: $q'),
        ),
      ),
    );

    await ask(tester, 'what colour is it');
    await tester.pumpAndSettle();

    expect(find.text('A pink diamond pattern.'), findsOneWidget);
    expect(find.text('what colour is it'), findsOneWidget);
    expect(find.text('Answering: what colour is it'), findsOneWidget);
  });

  testWidgets('shows the question immediately, before the answer arrives',
      (tester) async {
    final gate = Completer<AnalysisSheetReply>();
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) => gate.future,
        ),
      ),
    );

    await ask(tester, 'how many are there');
    await tester.pump();

    // The user's own words appear at once; a chat that swallows your message
    // until the model replies reads as broken.
    expect(find.text('how many are there'), findsOneWidget);
    expect(find.byKey(const Key('analysis-pending')), findsOneWidget);

    gate.complete(const AnalysisSheetReply('Two.'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analysis-pending')), findsNothing);
    expect(find.text('Two.'), findsOneWidget);
  });

  testWidgets('will not send a second question while one is in flight',
      (tester) async {
    final gate = Completer<AnalysisSheetReply>();
    var calls = 0;
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) {
            calls++;
            return gate.future;
          },
        ),
      ),
    );

    await ask(tester, 'first');
    await tester.pump();
    await ask(tester, 'second');
    await tester.pump();

    // Every call bills and counts against the daily cap, so a double tap must
    // not buy two.
    expect(calls, 1);

    gate.complete(const AnalysisSheetReply('done'));
    await tester.pumpAndSettle();
  });

  testWidgets('clears the field so the question is not sent twice',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) async => const AnalysisSheetReply('answer'),
        ),
      ),
    );

    await ask(tester, 'what colour is it');
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('analysis-question-field')),
    );
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('an error is shown in the transcript and can be retried',
      (tester) async {
    var first = true;
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) async {
            if (first) {
              first = false;
              return const AnalysisSheetReply(
                "Couldn't reach the service.",
                isError: true,
              );
            }
            return const AnalysisSheetReply('It is pink.');
          },
        ),
      ),
    );

    await ask(tester, 'what colour is it');
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach the service."), findsOneWidget);

    await ask(tester, 'what colour is it');
    await tester.pumpAndSettle();
    expect(find.text('It is pink.'), findsOneWidget);
  });

  testWidgets('an empty question is never sent', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) async {
            calls++;
            return const AnalysisSheetReply('answer');
          },
        ),
      ),
    );

    await ask(tester, '   ');
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('the caveat stays visible through the conversation',
      (tester) async {
    // Fixed and unconditional: a caveat that appears only sometimes teaches the
    // user that its absence means the answer IS reliable.
    await tester.pumpWidget(
      wrap(
        AnalysisResultSheet(
          initialText: 'A pink diamond pattern.',
          onAsk: (_) async => const AnalysisSheetReply('It is pink.'),
        ),
      ),
    );
    expect(find.text(kAnalysisCaveat), findsOneWidget);

    await ask(tester, 'what colour is it');
    await tester.pumpAndSettle();
    expect(find.text(kAnalysisCaveat), findsOneWidget);
  });

  testWidgets('onClosed fires when the sheet is dismissed', (tester) async {
    // This is what forgets the conversation. If it stops firing, re-opening a
    // photo silently resumes a transcript the user can no longer see.
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAnalysisResultSheet(
                context,
                initialText: 'A pink diamond pattern.',
                onAsk: (_) async => const AnalysisSheetReply('answer'),
                onClosed: () => closed = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('A pink diamond pattern.'), findsOneWidget);
    expect(closed, isFalse);

    await tester.tapAt(const Offset(400, 40)); // the scrim
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
