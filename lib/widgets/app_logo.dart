import 'package:flutter/material.dart';

/// The launcher icon, reused as the in-app logo so the auth screens match
/// what the user just tapped on their home screen.
const String kAppLogoAsset = 'assets/icon/icon.png';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    // The icon is a full-bleed square; rounding it here matches the adaptive
    // icon's mask closely enough without shipping a second, pre-cropped asset.
    return Semantics(
      label: 'LunarFlow logo',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          kAppLogoAsset,
          width: size,
          height: size,
          // 1024px source: decode at display size, not full resolution, on the
          // low-end target.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
