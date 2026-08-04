import 'package:flutter/material.dart';

Rect collectSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      !renderObject.size.isEmpty) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  final viewport = MediaQuery.maybeSizeOf(context) ?? const Size(1, 1);
  return Rect.fromCenter(
    center: viewport.center(Offset.zero),
    width: 1,
    height: 1,
  );
}
