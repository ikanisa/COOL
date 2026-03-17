import 'package:flutter/material.dart';
import '../../core/l10n/l10n.dart';

class CoolBrandMark extends StatelessWidget {
  const CoolBrandMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.coolAppLogo,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/images/cool_logo_mark.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}