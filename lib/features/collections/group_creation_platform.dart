import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Group metadata and membership are independent from Android SMS capture and
// payment capability. The router and repository retain signed-in session gates.
bool canCreateGroupsOnThisPlatform() => true;

@visibleForTesting
bool groupCreationPlatformAllowed({
  required bool isWeb,
  required TargetPlatform targetPlatform,
  String mobileEvidencePlatform = '',
}) => true;

bool shouldShowGroupCreationEntryOnThisPlatform() => true;

Future<void> openGroupCreation(BuildContext context) {
  context.go('/groups/create');
  return Future<void>.value();
}
