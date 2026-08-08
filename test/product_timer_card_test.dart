import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/product_timer_card.dart';
import 'package:provider/provider.dart';

/// The card ticks, so every test must unmount it before finishing — a pending
/// Timer fails the test by design. That guard is the whole reason `dispose`
/// discipline here is not optional: the same leak on Home would hang
/// `pumpAndSettle` across the suite.
void main() {
  late AppDatabase db;
  late ProductSessionProvider provider;

  final insertedAt = DateTime(2026, 8, 8, 9, 14);
  late DateTime now;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = ProductSessionProvider(
        ProductSessionRepository(ReminderRepository(db)));
    now = insertedAt.add(const Duration(hours: 4, minutes: 20));
  });
  tearDown(() => db.close());

  ProductSession session({
    ProductType product = ProductType.tampon,
    Duration interval = const Duration(hours: 6),
  }) =>
      ProductSession(
          insertedAt: insertedAt, product: product, interval: interval);

  Future<void> pump(WidgetTester tester, ProductSession s) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ProductSessionProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProductTimerCard(session: s, clock: () => now),
          ),
        ),
      ),
    );
  }

  /// Unmounts the card so its Timer is cancelled before the test ends.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  group('running state', () {
    testWidgets('shows the product, the start clock and elapsed time',
        (tester) async {
      await pump(tester, session());

      expect(find.text('Tampon'), findsOneWidget);
      expect(find.textContaining('09:14'), findsOneWidget);
      expect(find.textContaining('4h 20m'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('elapsed text advances one minute after pump(1 minute)',
        (tester) async {
      await pump(tester, session());
      expect(find.textContaining('4h 20m'), findsOneWidget);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(find.textContaining('4h 21m'), findsOneWidget);
      expect(find.textContaining('4h 20m'), findsNothing);

      await unmount(tester);
    });

    testWidgets('the elapsed value is recomputed, never accumulated',
        (tester) async {
      // Simulates the app being backgrounded (or the screen locked, where
      // TickerMode freezes animations) for three hours: one tick later the
      // display must be right, not three hours behind.
      await pump(tester, session());
      now = insertedAt.add(const Duration(hours: 7, minutes: 20));
      await tester.pump(const Duration(minutes: 1));

      expect(find.textContaining('7h 20m'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('re-aligns when the session restarts under it', (tester) async {
      await pump(tester, session());
      final restarted = ProductSession(
        insertedAt: now,
        product: ProductType.tampon,
        interval: const Duration(hours: 6),
      );
      await pump(tester, restarted);

      expect(find.textContaining('0m'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('past-target state', () {
    testWidgets('says "past the 6h you set", never "overdue"', (tester) async {
      now = insertedAt.add(const Duration(hours: 6, minutes: 5));
      await pump(tester, session());

      expect(find.textContaining('past the 6h you set'), findsOneWidget);
      expect(find.textContaining('overdue'), findsNothing);
      expect(find.textContaining('Overdue'), findsNothing);

      await unmount(tester);
    });

    testWidgets('discloses a possibly-missed reminder past 30 minutes',
        (tester) async {
      // The structural defeat of inference-from-silence: without this, a
      // notification silently dropped by Doze reads as "not time yet".
      now = insertedAt.add(const Duration(hours: 6, minutes: 31));
      await pump(tester, session());

      expect(find.textContaining('may not have arrived on time'),
          findsOneWidget);

      await unmount(tester);
    });

    testWidgets('does not disclose a missed reminder before 30 minutes',
        (tester) async {
      now = insertedAt.add(const Duration(hours: 6, minutes: 5));
      await pump(tester, session());

      expect(find.textContaining('may not have arrived'), findsNothing);

      await unmount(tester);
    });

    testWidgets('shows attributed manufacturer guidance only for capped '
        'products', (tester) async {
      now = insertedAt.add(const Duration(hours: 6, minutes: 5));
      await pump(tester, session(product: ProductType.tampon));
      expect(find.textContaining('Tampon packaging'), findsOneWidget);
      await unmount(tester);

      await pump(tester, session(product: ProductType.pad));
      expect(find.textContaining('packaging'), findsNothing);
      expect(find.textContaining('manufacturer'), findsNothing);
      await unmount(tester);
    });
  });

  group('actions', () {
    testWidgets('"Changed" restarts the same product from now', (tester) async {
      await provider.start(ProductType.tampon,
          interval: const Duration(hours: 6), now: insertedAt);
      await pump(tester, provider.session!);

      await tester.tap(find.text('Changed'));
      await tester.pumpAndSettle();

      expect(provider.session?.product, ProductType.tampon);
      expect(provider.session?.interval, const Duration(hours: 6));
      expect(provider.session?.insertedAt, isNot(insertedAt));

      await unmount(tester);
    });

    testWidgets('"Removed" ends the session', (tester) async {
      await provider.start(ProductType.tampon,
          interval: const Duration(hours: 6), now: insertedAt);
      await pump(tester, provider.session!);

      await tester.tap(find.text('Removed'));
      await tester.pumpAndSettle();

      expect(provider.session, null);

      await unmount(tester);
    });
  });

  group('copy guardrails', () {
    testWidgets('never reassures, alarms, or counts down', (tester) async {
      for (final elapsed in [
        const Duration(hours: 1),
        const Duration(hours: 6, minutes: 5),
        const Duration(hours: 9),
      ]) {
        now = insertedAt.add(elapsed);
        await pump(tester, session());

        for (final banned in [
          'safe',
          'Safe',
          'risk',
          'TSS',
          'toxic',
          'danger',
          'urgent',
          'warning',
          'emergency',
          'remaining',
          'left',
          'until',
          "you're fine",
        ]) {
          expect(find.textContaining(banned), findsNothing,
              reason: '"$banned" must not appear at $elapsed');
        }
        await unmount(tester);
      }
    });

    testWidgets('shows no progress bar — a bar is a countdown drawn in pixels',
        (tester) async {
      now = insertedAt.add(const Duration(hours: 3));
      await pump(tester, session());

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await unmount(tester);
    });
  });
}
