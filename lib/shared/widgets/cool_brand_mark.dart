import 'package:flutter/material.dart';

class CoolBrandMark extends StatelessWidget {
  const CoolBrandMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/cool_logo_mark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
