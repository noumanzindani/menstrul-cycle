import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/product_timer_start_card.dart';

void main() {
  late AppDatabase db;
  late ProductSessionProvider provider;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = ProductSessionProvider(
        ProductSessionRepository(ReminderRepository(db)));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ProductSessionProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ProductTimerStartCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('idle card', () {
    testWidgets('offers one chip per product', (tester) async {
      await pump(tester);
      for (final t in ProductType.values) {
        expect(find.text(t.label), findsOneWidget);
      }
    });

    testWidgets('one tap starts a session at that product default',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Cup / disc'));
      await tester.pumpAndSettle();

      expect(provider.session?.product, ProductType.cupOrDisc);
      expect(provider.session?.interval, ProductType.cupOrDisc.defaultDuration);
    });

    testWidgets('sets the reliance expectation up front', (tester) async {
      // The app never claims delivery. Saying so at the point of first use is
      // what makes an inexact, droppable alarm an honest thing to ship.
      await pump(tester);
      expect(find.textContaining('may arrive late, or not at all'),
          findsOneWidget);
    });

    testWidgets('never reassures, alarms or counts down', (tester) async {
      await pump(tester);
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
        'time\'s up',
      ]) {
        expect(find.textContaining(banned), findsNothing, reason: banned);
      }
    });
  });

  group('duration sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Set a different time'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts a session with the chosen duration', (tester) async {
      await pump(tester);
      await openSheet(tester);

      // Default tampon 4h; two decrements of 30m -> 3h.
      await tester.tap(find.text('Tampon').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(provider.session?.product, ProductType.tampon);
      expect(provider.session?.interval, const Duration(hours: 3));
    });

    testWidgets('will not raise a tampon past the 8h manufacturer cap',
        (tester) async {
      await pump(tester);
      await openSheet(tester);
      await tester.tap(find.text('Tampon').last);
      await tester.pumpAndSettle();

      // Far more taps than needed to reach the cap from the 4h default.
      for (var i = 0; i < 30; i++) {
        await tester.tap(find.byIcon(Icons.add));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(provider.session?.interval, ProductType.tampon.maxDuration);
      expect(provider.session!.interval,
          lessThanOrEqualTo(const Duration(hours: 8)));
    });

    testWidgets('explains the cap by attribution, never as the app\'s own '
        'advice', (tester) async {
      await pump(tester);
      await openSheet(tester);
      await tester.tap(find.text('Tampon').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Tampon packaging'), findsOneWidget);
      expect(find.textContaining('we recommend'), findsNothing);
      expect(find.textContaining('We recommend'), findsNothing);
      expect(find.textContaining('should'), findsNothing);
    });

    testWidgets('points at the product\'s own instructions', (tester) async {
      await pump(tester);
      await openSheet(tester);
      expect(
          find.textContaining(
              'Follow the instructions that came with your product'),
          findsOneWidget);
    });

    testWidgets('shows no manufacturer guidance for an uncapped product',
        (tester) async {
      await pump(tester);
      await openSheet(tester);
      await tester.tap(find.text('Pad').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('packaging'), findsNothing);
      expect(find.textContaining('manufacturers'), findsNothing);
    });

    testWidgets('will not go below a sane floor', (tester) async {
      await pump(tester);
      await openSheet(tester);
      for (var i = 0; i < 30; i++) {
        await tester.tap(find.byIcon(Icons.remove));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(provider.session!.interval,
          greaterThanOrEqualTo(const Duration(minutes: 30)));
    });
  });
}
