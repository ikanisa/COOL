import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env/app_env.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import 'group_invitation_transport.dart';
import '../../shared/utils/collect_share_links.dart';
import '../../shared/utils/collect_share_origin.dart';

String groupDeepLinkFor(AppEnv env, CollectCollection collection) {
  return collectPublicLink(env, ['c', collection.slug.trim()]);
}

String groupDeepLinkForCode(
  AppEnv env,
  CollectCollection collection,
  String? shareCode,
) {
  final code = shareCode?.trim();
  return collectPublicLink(env, [
    'c',
    code == null || code.isEmpty ? collection.slug.trim() : code,
  ]);
}

String groupShareMessageFor(
  AppEnv env,
  CollectCollection collection, {
  String? shareCode,
}) {
  final link = groupDeepLinkForCode(env, collection, shareCode);
  return 'Join ${collection.title} for ${collection.collectionType.shortPurpose.toLowerCase()} on Collect: $link';
}

/// Binds an output to its current account, group, repository and visible route.
/// Navigation invalidates the scope even while a covered screen stays mounted.
class GroupInvitationOutputScope {
  GroupInvitationOutputScope(
    BuildContext context,
    WidgetRef ref,
    String groupId, {
    bool requireOwner = false,
  }) : _context = context,
       _ref = ref,
       _repository = ref.read(collectRepositoryProvider.notifier),
       _route = ModalRoute.of(context) {
    _authority = _repository.captureGroupInvitationAuthority(
      groupId,
      requireOwner: requireOwner,
    );
    _route?.secondaryAnimation?.addListener(_navigationChanged);
    try {
      check();
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  final BuildContext _context;
  final WidgetRef _ref;
  final CollectRepository _repository;
  final ModalRoute<dynamic>? _route;
  late final CollectInvitationAuthority _authority;
  bool _invalid = false;
  void _navigationChanged() {
    if (_route?.isCurrent == false) {
      _invalid = true;
    }
  }

  bool get isCurrent {
    if (!_invalid &&
        (!_context.mounted ||
            _route?.isCurrent == false ||
            !identical(
              _repository,
              _ref.read(collectRepositoryProvider.notifier),
            ) ||
            !_authority.isCurrent)) {
      _invalid = true;
    }
    return !_invalid;
  }

  void check() {
    if (!isCurrent) {
      throw StateError(
        'Your account or invitation changed. Open the invitation again.',
      );
    }
  }

  void dispose() {
    _invalid = true;
    _route?.secondaryAnimation?.removeListener(_navigationChanged);
    _authority.dispose();
  }
}

Future<void> shareGroupDeepLink({
  required BuildContext context,
  required WidgetRef ref,
  required CollectCollection collection,
  String? shareCode,
}) async {
  final scope = GroupInvitationOutputScope(context, ref, collection.id);
  final env = ref.read(appEnvProvider);
  final transport = ref.read(groupInvitationTransportProvider);
  try {
    final code = await ref
        .read(collectRepositoryProvider.notifier)
        .getGroupShareCode(collection.id);
    scope.check();
    if (!context.mounted) return;
    final link = groupDeepLinkForCode(env, collection, code);
    try {
      await transport.shareLink(
        collection.title,
        groupShareMessageFor(env, collection, shareCode: code),
        collectSharePositionOrigin(context),
      );
    } catch (_) {
      scope.check();
      await transport.copyLink(link);
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
    }
  } finally {
    scope.dispose();
  }
}

Future<void> copyGroupDeepLink({
  required BuildContext context,
  required WidgetRef ref,
  required CollectCollection collection,
}) async {
  final scope = GroupInvitationOutputScope(context, ref, collection.id);
  final env = ref.read(appEnvProvider);
  try {
    final code = await ref
        .read(collectRepositoryProvider.notifier)
        .getGroupShareCode(collection.id);
    scope.check();
    await ref
        .read(groupInvitationTransportProvider)
        .copyLink(groupDeepLinkForCode(env, collection, code));
    if (!context.mounted || !scope.isCurrent) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
  } finally {
    scope.dispose();
  }
}
