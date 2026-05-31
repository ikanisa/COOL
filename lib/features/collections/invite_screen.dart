import 'package:flutter/material.dart';

import 'share_screen.dart';

class InviteScreen extends StatelessWidget {
  const InviteScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context) => ShareScreen(collectionId: collectionId);
}
