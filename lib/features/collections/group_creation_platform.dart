import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

bool canCreateGroupsOnThisPlatform() {
  return kIsWeb || defaultTargetPlatform == TargetPlatform.android;
}

bool shouldShowGroupCreationEntryOnThisPlatform() {
  return kIsWeb || defaultTargetPlatform == TargetPlatform.android;
}

Future<void> openGroupCreation(BuildContext context) {
  if (canCreateGroupsOnThisPlatform()) {
    context.go('/groups/create');
    return Future<void>.value();
  }
  return showAndroidGroupCreationOnlyDialog(context);
}

Future<void> showAndroidGroupCreationOnlyDialog(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CollectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoSecurityBanner(
            title: 'Join options',
            message: 'Group creation is available only on Android',
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
          CollectButton(
            label: 'Scan QR',
            icon: CollectIcons.qr,
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/groups/scan');
            },
            expand: true,
          ),
          CollectSpacing.gap12,
          CollectButton(
            label: 'Groups',
            icon: CollectIcons.collections,
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/groups');
            },
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
    ),
  );
}
