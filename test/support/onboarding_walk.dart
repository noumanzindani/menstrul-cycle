import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Driving the onboarding wizard, which since 2026-09-14 REFUSES to advance
/// past an unanswered question.
///
/// This repo normally defines test helpers inline per file. This one is shared
/// because two suites need the same walk and getting it wrong is silent: a
/// helper that taps Continue without answering does not fail, it spins until
/// the loop bound runs out and then reports a missing page — which reads like
/// a routing bug rather than an unanswered question.
///
/// Three things here are easy to get wrong and are handled once:
///
/// - **Groups are addressed by key, not by label.** Each baseline page renders
///   the same option list twice, once for "generally" and once for "today".
///   `find.text('High libido')` cannot tell them apart.
/// - **`ListView` builds lazily**, so a group below the fold has no element and
///   `ensureVisible` has nothing to scroll to. [tapInGroup] scrolls first.
/// - **[answerVisiblePage] assumes an untouched page.** It taps chips
///   unconditionally, and a tap on an already-selected chip is a DESELECT. A
///   test that pre-answers part of a page must finish that page by hand.
const periodQuestion = 'When did your last period start?';
const cycleQuestion = 'How long is your cycle, usually?';
const dobQuestion = 'When were you born?';
const bodyQuestion = 'A few more details about you';
const contraceptionQuestion = 'Are you using contraception?';
const sexQuestion = 'How often do you have sex?';
const shxQuestion = 'Have you ever experienced any of these?';
const soloQuestion = 'How often do you masturbate?';
const modeQuestion = 'What are you using LunarFlow for?';

const introTitles = ['Welcome to LunarFlow', 'Your data, on your terms'];

/// Every page heading the wizard can show, in order.
const allPageHeadings = [
  ...introTitles,
  periodQuestion,
  cycleQuestion,
  dobQuestion,
  bodyQuestion,
  contraceptionQuestion,
  sexQuestion,
  shxQuestion,
  soloQuestion,
  modeQuestion,
];

/// The heading of the page currently on screen, or null if none matches.
String? visibleHeading(WidgetTester tester) {
  for (final h in allPageHeadings) {
    if (find.text(h).hitTestable().evaluate().isNotEmpty) return h;
  }
  return null;
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// Taps a label that is unambiguous on the page it appears on.
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).hitTestable().first);
  await tester.pumpAndSettle();
}

/// Taps the option labelled [label] inside the chip group keyed [groupKey],
/// scrolling the group into existence first.
Future<void> tapInGroup(
  WidgetTester tester,
  String groupKey,
  String label,
) async {
  final group = find.byKey(Key(groupKey));
  if (group.evaluate().isEmpty) {
    await tester.scrollUntilVisible(group, 120,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }
  final chip = find.descendant(of: group, matching: find.text(label));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Answers whatever page is on screen with the LEAST the wizard will accept,
/// taking the escape option wherever one exists.
///
/// This doubles as the proof that the escape options work: if any required set
/// lacked an answer a user could honestly give, this could not get past it.
Future<void> answerVisiblePage(WidgetTester tester) async {
  bool on(String q) => find.text(q).hitTestable().evaluate().isNotEmpty;

  if (on(periodQuestion)) {
    // The grid's own "today" cell — always present, always in range.
    await tapText(tester, '${DateTime.now().day}');
  } else if (on(dobQuestion)) {
    await tapText(tester, '${DateTime.now().year - 8}');
  } else if (on(bodyQuestion)) {
    await tester.enterText(
        find.byKey(const Key('onboarding-height-field')), '165');
    await tester.enterText(
        find.byKey(const Key('onboarding-weight-field')), '61.5');
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byKey(const Key('menarche-stepper')),
      matching: find.byIcon(Icons.add),
    ));
    await tester.pumpAndSettle();
  } else if (on(contraceptionQuestion)) {
    await tapText(tester, 'None');
  } else if (on(sexQuestion)) {
    await tapText(tester, 'Never');
    await tapInGroup(tester, 'sex-today', 'None');
  } else if (on(shxQuestion)) {
    await tapInGroup(tester, 'shx-history', 'None of these');
    await tapInGroup(tester, 'libido-baseline', 'Medium libido');
    await tapInGroup(tester, 'shx-today', 'None of these');
    await tapInGroup(tester, 'libido-today', 'High libido');
  } else if (on(soloQuestion)) {
    await tapText(tester, 'Never');
    await tapInGroup(tester, 'solo-ways', 'Prefer not to say');
    await tapInGroup(tester, 'solo-time', 'Prefer not to answer');
    await tapInGroup(tester, 'solo-today', 'Not today');
  }
}

/// Walks to [question], answering every page on the way.
///
/// The page it stops on is left UNANSWERED, so a caller can answer it itself.
///
/// Continue is pressed FIRST and the page is only answered when that press did
/// not move — which is what makes this idempotent. Answering unconditionally
/// would re-tap a page the caller had already filled in, and on a chip or a
/// date grid a second tap is a DESELECT, so the helper would undo the very
/// answer the test was about to assert on.
Future<void> walkTo(WidgetTester tester, String question) async {
  // A bound, not a page count: the wizard grows, and a bound equal to the page
  // count silently stops working the day a page is added.
  for (var i = 0; i < 30 && find.text(question).evaluate().isEmpty; i++) {
    final before = visibleHeading(tester);
    await tapContinue(tester);
    if (visibleHeading(tester) == before) {
      await answerVisiblePage(tester);
      await tapContinue(tester);
    }
  }
  expect(find.text(question), findsOneWidget,
      reason: 'the wizard never reached "$question" — either a required '
          'question has no answer this helper can give, or the page is gone');
}

/// Answers every remaining page and presses "Get started".
Future<void> finishWizard(WidgetTester tester) async {
  await walkTo(tester, modeQuestion);
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
}
