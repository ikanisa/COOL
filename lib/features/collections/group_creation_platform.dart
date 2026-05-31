import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

bool canCreateGroupsOnThisPlatform() {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

Future<void> openGroupCreation(BuildContext context) {
  if (canCreateGroupsOnThisPlatform()) {
    context.go('/groups/create');
    return Future<void>.value();
  }
  return showAndroidGroupCreationOnlyDialog(context);
}

Future<void> showAndroidGroupCreationOnlyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text('group creation is available only on Android'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
