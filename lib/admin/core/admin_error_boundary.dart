import 'package:flutter/material.dart';

class AdminErrorBoundary extends StatelessWidget {
  const AdminErrorBoundary({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
