import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// Onboarding answers are MANDATORY as of 2026-09-14, reversing the wizard's
/// original posture (every answer skippable, a skip storing NULL).
///
/// Two things this file exists to hold, because both are easy to lose:
///
/// 1. **Every required question must be answerable.** A required question whose
///    options do not cover the user's situation deadlocks the wizard — nobody
///    can finish, and the app cannot be opened at all. The escape options are
///    load-bearing, not cosmetic, and [_completesUsingOnlyEscapeAnswers] is the
///    test that proves it.
///
///    **One exception, 2026-09-18:** the solo-ways question lost its "prefer
///    not to say" option at the owner's request. It does not deadlock — hands,
///    toy, water and a free-text "Other" all still finish the wizard — but it
///    is now the only REQUIRED question here that cannot be honestly DECLINED,
///    and its sibling on the same page still can be. Written down so the
///    asymmetry stays a decision rather than becoming an accident.
/// 2. **Continue is the only exit.** The refusal lives on the Continue path, so
///    a `PageView` a user can swipe makes every check advisory.
class _FakeSignedInAuthService implements AuthService {
  static const _user = AppUser(uid: 'test-uid', email: 'test@example.com');

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_user);
  @override
  AppUser? get currentUser => _user;
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
}

SyncTrigger _testSyncTrigger(AppDatabase db) => SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    );

const _periodQuestion = 'When did your last period start?';
const _dobQuestion = 'When were you born?';
const _bodyQuestion = 'A few more details about you';
const _contraceptionQuestion = 'Are you using contraception?';
const _pregnancyQuestion = 'Have you been pregnant in the last 3 months?';
const _sexQuestion = 'How often do you have sex?';
const _shxQuestion = 'Have you ever experienced any of these?';
const _soloQuestion = 'How often do you masturbate?';
const _modeQuestion = 'What are you using LunarFlow for?';

Future<AppDatabase> _pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    LunarFlowApp(
      database: db,
      authService: _FakeSignedInAuthService(),
      syncTrigger: _testSyncTrigger(db),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Taps the option labelled [label] inside the chip group keyed [groupKey].
///
/// Addressed by GROUP rather than by label index, because each baseline page
/// renders the same option list twice — once for "generally", once for "today"
/// — and the two are indistinguishable by label alone.
///
/// `scrollUntilVisible` rather than `ensureVisible`: a `ListView` builds its
/// children lazily, so a group below the fold has no element yet and there is
/// nothing for `ensureVisible` to scroll to.
Future<void> _tapInGroup(
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

/// Taps a label that is unambiguous on the page it appears on.
Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label).hitTestable().first;
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// Answers whatever page is on screen with the LEAST the wizard will accept,
/// choosing the escape option wherever one exists.
///
/// This doubles as the proof the escape options work: if any required set
/// lacked an answerable option, this helper could not get past it.
Future<void> _answerVisiblePage(WidgetTester tester) async {
  if (find.text(_periodQuestion).hitTestable().evaluate().isNotEmpty) {
    // The grid's own "today" cell — always present, always in range.
    await _tapText(tester, '${DateTime.now().day}');
    return;
  }
  if (find.text(_dobQuestion).hitTestable().evaluate().isNotEmpty) {
    await _tapText(tester, '${DateTime.now().year - 8}');
    return;
  }
  if (find.text(_bodyQuestion).hitTestable().evaluate().isNotEmpty) {
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
    return;
  }
  if (find.text(_contraceptionQuestion).hitTestable().evaluate().isNotEmpty) {
    await _tapText(tester, 'None');
    return;
  }
  if (find.text(_pregnancyQuestion).hitTestable().evaluate().isNotEmpty) {
    // The escape option: proves the page is answerable without disclosing.
    await _tapInGroup(tester, 'pregnancy-status', 'Prefer not to say');
    return;
  }
  if (find.text(_sexQuestion).hitTestable().evaluate().isNotEmpty) {
    await _tapText(tester, 'Never');
    await _tapInGroup(tester, 'sex-today', 'None');
    return;
  }
  if (find.text(_shxQuestion).hitTestable().evaluate().isNotEmpty) {
    // "None of these" appears twice on this page — once for the ever-happened
    // set, once for today — and both must be answered. The finder is
    // re-evaluated each pass on purpose: tapping rebuilds the tree, which
    // invalidates any Element list captured before the first tap.
    // Four required answers on one page: what has ever happened, general
    // libido, what happened today, and today's libido.
    await _tapInGroup(tester, 'shx-history', 'None of these');
    await _tapInGroup(tester, 'libido-baseline', 'Medium libido');
    await _tapInGroup(tester, 'shx-today', 'None of these');
    await _tapInGroup(tester, 'libido-today', 'High libido');
    return;
  }
  if (find.text(_soloQuestion).hitTestable().evaluate().isNotEmpty) {
    await _tapText(tester, 'Never');
    await _tapInGroup(tester, 'solo-ways', 'Hands');
    await _tapInGroup(tester, 'solo-time', 'Prefer not to answer');
    await _tapInGroup(tester, 'solo-today', 'Not today');
    return;
  }
}

/// Walks to [question], answering every page on the way.
Future<void> _walkTo(WidgetTester tester, String question) async {
  for (var i = 0; i < 30 && find.text(question).evaluate().isEmpty; i++) {
    await _answerVisiblePage(tester);
    await _tapContinue(tester);
  }
  expect(find.text(question), findsOneWidget,
      reason: 'the wizard refused to advance to "$question" — a required '
          'question is unanswerable');
}

void main() {
  group('the skip affordances are gone', () {
    testWidgets('the last-period page no longer offers "I\'m not sure"',
        (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _periodQuestion);
      expect(find.text("I'm not sure"), findsNothing);
    });

    testWidgets('the birth-date page no longer offers a decline',
        (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _dobQuestion);
      expect(find.text("I'd rather not say"), findsNothing);
    });

    testWidgets('the profile page no longer claims to be optional',
        (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _bodyQuestion);
      expect(find.textContaining('All optional'), findsNothing);
    });
  });

  group('an unanswered question refuses to advance', () {
    testWidgets('the last-period date is required', (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _periodQuestion);

      await _tapContinue(tester);
      expect(find.text(_periodQuestion), findsOneWidget,
          reason: 'the wizard advanced without a date');
      expect(find.textContaining('Pick a date'), findsOneWidget);
    });

    testWidgets('the birth date is required', (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _dobQuestion);

      await _tapContinue(tester);
      expect(find.text(_dobQuestion), findsOneWidget);
    });

    testWidgets('a blank height is refused, not stored as null',
        (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _bodyQuestion);

      await _tapContinue(tester);
      expect(find.text(_bodyQuestion), findsOneWidget);
      expect(find.textContaining('Enter a height'), findsOneWidget);
    });

    testWidgets('contraception is required', (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _contraceptionQuestion);

      await _tapContinue(tester);
      expect(find.text(_contraceptionQuestion), findsOneWidget);
    });

    testWidgets('both halves of the sex page are required', (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _sexQuestion);

      await _tapContinue(tester);
      expect(find.text(_sexQuestion), findsOneWidget);

      // Answering only the baseline is still not enough: the "today" half is
      // a separate required answer.
      await _tapText(tester, 'Never');
      await _tapContinue(tester);
      expect(find.text(_sexQuestion), findsOneWidget,
          reason: 'the today half was not enforced');
    });

    testWidgets('the new solo questions are required', (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _soloQuestion);

      await _tapText(tester, 'Never');
      await _tapInGroup(tester, 'solo-today', 'Not today');
      await _tapContinue(tester);
      expect(find.text(_soloQuestion), findsOneWidget,
          reason: 'ways and time-to-satisfaction were not enforced');
    });

    testWidgets('"Other" is only answered once the box has words in it',
        (tester) async {
      await _pumpOnboarding(tester);
      await _walkTo(tester, _soloQuestion);

      await _tapText(tester, 'Never');
      await _tapInGroup(tester, 'solo-ways', 'Other');
      await _tapInGroup(tester, 'solo-time', 'Prefer not to answer');
      await _tapInGroup(tester, 'solo-today', 'Not today');

      await _tapContinue(tester);
      expect(find.text(_soloQuestion), findsOneWidget,
          reason: 'an empty "Other" box counted as an answer, which stores '
              'that there is another way and nothing about what it is');

      await tester.enterText(
          find.byKey(const Key('solo-ways-other-field')), 'Something else');
      await tester.pumpAndSettle();
      await _tapContinue(tester);
      expect(find.text(_soloQuestion), findsNothing,
          reason: 'a filled "Other" box was still refused');
    });
  });

  testWidgets('the wizard completes using every escape answer that still '
      'exists, and stores them', (tester) async {
    // THE test this file exists for. Every required set must have an answer a
    // user in the "none of this applies to me" case can honestly give.
    //
    // Solo-ways is answered with 'Hands' rather than a decline, because since
    // 2026-09-18 it has no decline to give — see the exception in the file
    // header. That one line is the difference between this test proving the
    // rule and merely proving the wizard finishes.
    final db = await _pumpOnboarding(tester);
    await _walkTo(tester, _modeQuestion);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    final settings = await db.getSettings();
    expect(settings.onboardingComplete, isTrue,
        reason: 'a user with nothing to report cannot get into the app');

    final b = decodeSexualBaseline(settings.sexualHealthBaseline);
    expect(b.sexFrequency, 'freq_never');
    expect(b.soloFrequency, 'freq_never');
    expect(b.soloWays, {'slfw_hands'});
    expect(b.satisfactionTime, kSatPrivate);
    expect(b.history, {kShxNone});
  });

  testWidgets('SWIPING cannot bypass a required question', (tester) async {
    final db = await _pumpOnboarding(tester);
    await _walkTo(tester, _periodQuestion);

    for (var i = 0; i < 6; i++) {
      await tester.dragFrom(const Offset(300, 150), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    expect(find.text(_periodQuestion), findsOneWidget,
        reason: 'a swipe walked past an unanswered required question');
    final settings = await db.getSettings();
    expect(settings.onboardingComplete, isFalse);
  });

  group('the escape option is mutually exclusive with the real answers', () {
    testWidgets('choosing a symptom clears "None of these", and vice versa',
        (tester) async {
      // Otherwise the stored history reads "I have never had any of these, and
      // I have had pain during sex" — a contradiction no reader can resolve.
      final db = await _pumpOnboarding(tester);
      await _walkTo(tester, _shxQuestion);

      await _tapInGroup(tester, 'shx-history', 'Pain during sex');
      await _tapInGroup(tester, 'shx-history', 'None of these');

      // The rest of this page is answered by hand rather than by
      // [_answerVisiblePage], which assumes a page nobody has touched: it taps
      // "None of these" unconditionally, and on a chip that is already selected
      // that is a DESELECT — it would undo the very thing under test.
      await _tapInGroup(tester, 'libido-baseline', 'Medium libido');
      await _tapInGroup(tester, 'shx-today', 'None of these');
      await _tapInGroup(tester, 'libido-today', 'High libido');
      await _tapContinue(tester);

      await _walkTo(tester, _modeQuestion);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      final b =
          decodeSexualBaseline((await db.getSettings()).sexualHealthBaseline);
      expect(b.history, {kShxNone},
          reason: '"none of these" must clear the symptoms it contradicts');
    });
  });
}
