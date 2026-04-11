import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand/app_brand.dart';
import '../../core/l10n/l10n.dart';

/// Brand logo mark using the transparent-background variant.
///
/// The transparent PNG naturally inherits whatever screen background
/// is behind it, guaranteeing a seamless color match on all surfaces.
class CoolBrandMark extends ConsumerWidget {
  const CoolBrandMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(appBrandProvider);
    return Semantics(
      label: context.l10n.coolAppLogo,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          brand.logoTransparentAssetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
