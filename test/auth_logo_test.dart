import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/screens/auth/sign_in_screen.dart';
import 'package:menstrul_track/screens/auth/sign_up_screen.dart';
import 'package:menstrul_track/widgets/app_logo.dart';
import 'package:provider/provider.dart';

import 'auth_screens_test.dart' show FakeAuthService;

Widget _wrap(Widget child, FakeAuthService fake) => ChangeNotifierProvider(
      create: (_) => AuthProvider(fake),
      child: MaterialApp(home: child),
    );

Finder _logoImage() => find.descendant(
      of: find.byType(AppLogo),
      matching: find.byWidgetPredicate((w) {
        if (w is! Image) return false;
        // cacheWidth wraps the asset in a ResizeImage.
        var provider = w.image;
        if (provider is ResizeImage) provider = provider.imageProvider;
        return provider is AssetImage && provider.assetName == kAppLogoAsset;
      }),
    );

void main() {
  late FakeAuthService fake;
  setUp(() => fake = FakeAuthService());
  tearDown(() => fake.dispose());

  testWidgets('sign-in shows the app logo', (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));
    expect(_logoImage(), findsOneWidget);
  });

  testWidgets('create-account shows the app logo', (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));
    expect(_logoImage(), findsOneWidget);
  });

  testWidgets('the logo is announced as the app name', (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));
    expect(find.bySemanticsLabel('LunarFlow logo'), findsOneWidget);
  });
}
