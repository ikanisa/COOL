import 'package:flutter/material.dart';

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(label: Text(label));
}
