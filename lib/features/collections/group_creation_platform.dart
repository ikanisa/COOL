import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

const _mobileEvidencePlatform = String.fromEnvironment(
  'COLLECT_MOBILE_EVIDENCE_PLATFORM',
);

bool canCreateGroupsOnThisPlatform() {
  return groupCreationPlatformAllowed(
    isWeb: kIsWeb,
    targetPlatform: defaultTargetPlatform,
    mobileEvidencePlatform: _mobileEvidencePlatform,
  );
}

@visibleForTesting
bool groupCreationPlatformAllowed({
  required bool isWeb,
  required TargetPlatform targetPlatform,
  String mobileEvidencePlatform = '',
}) {
  return true;
}

bool shouldShowGroupCreationEntryOnThisPlatform() {
  return canCreateGroupsOnThisPlatform();
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
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (context) => CollectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoSecurityBanner(
            title: 'Group creation',
            message: 'Group creation is available on this device.',
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
