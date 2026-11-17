import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_repository_base.dart';
import 'cloudflare_admin_data_refresh.dart';
import 'cloudflare_admin_operating_pages.dart' show operatingRecoverySchema;
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_request_identity.dart';
import 'cloudflare_admin_session.dart';

/// The existing public form keeps its fields, labels and defaults. This bridge
/// changes only its transport; no person, financial member or PIN enters it.
Map<String, dynamic> platformPublicGroupBody(Map<String, dynamic> draft) => {
  'title': draft['p_title'],
  'description': draft['p_description'],
  'collection_type': draft['p_collection_type'],
  if ((draft['p_category_subtype'] as String).isNotEmpty)
    'category_subtype': draft['p_category_subtype'],
  'purpose_label': draft['p_purpose_label'],
  'receiver': {
    'label': draft['p_receiver_label'],
    'network': draft['p_network'],
    'momo_number_or_code': draft['p_momo_code'],
  },
  'status': 'active',
  'visibility': 'public_approved',
  'is_platform_sponsored': true,
  'reason': draft['p_reason'],
};

class CloudflarePublicGroupCreateButton extends ConsumerStatefulWidget {
  const CloudflarePublicGroupCreateButton({
    required this.onCreatePrivate,
    required this.onDone,
    super.key,
  });
  final VoidCallback onCreatePrivate, onDone;
  @override
  ConsumerState<CloudflarePublicGroupCreateButton> createState() =>
      _PublicGroupCreateState();
}

class _PublicGroupCreateState
    extends ConsumerState<CloudflarePublicGroupCreateButton> {
  static const _family = 'operating-creategroup', _resource = 'new';
  final _menu = GlobalKey<PopupMenuButtonState<String>>();
  bool _busy = false;

  bool _allowed(CloudflareAdminUser? user) =>
      user != null &&
      user.usesCanonicalEvidence &&
      user.role == AdminAccountRole.owner &&
      user.expiresAt.isAfter(DateTime.now()) &&
      const [
        'collections.create',
        'collections.manage',
        'receivers.manage',
      ].every(user.permissions.contains);

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _public() async {
    if (_busy) return;
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    if (!_allowed(user) || !user!.hasRecentSensitiveVerification()) {
      _message('Verify your current Admin email before continuing.');
      return;
    }
    final fence = ref
        .read(cloudflareAdminSessionProvider.notifier)
        .authorityFence;
    bool current() {
      if (!mounted || !cloudflareAdminAuthorityIsCurrent(ref, fence)) {
        return false;
      }
      final latest = ref.read(cloudflareAdminSessionProvider).asData?.value;
      return _allowed(latest) &&
          latest!.authorityKey == user.authorityKey &&
          latest.hasRecentSensitiveVerification();
    }

    final repository = ref.read(adminRepositoryProvider);
    if (repository is! CloudflareAdminRepository) return;
    final store = ref.read(adminPendingAttemptStoreProvider);
    final schema = operatingRecoverySchema(CloudflareOperation.createGroup);
    setState(() => _busy = true);
    try {
      final pending = store.restore(
        family: _family,
        resourceId: _resource,
        schema: schema,
      );
      if (!store.storageAvailable) {
        throw const AdminAccountException(
          'Recovery storage is unavailable. Check Requests before creating a group.',
        );
      }
      if (pending != null) {
        // Reopening the same existing action after an unknown response performs
        // only a GET. Even not_found does not silently replay a creation.
        final result = await repository.operatingRequest(pending.requestKey);
        if (!current()) return;
        if (result['status'] == 'succeeded') {
          final receipt = CloudflareOperationReceipt.parse(
            Map<String, dynamic>.from(result['receipt'] as Map),
          );
          if (receipt.resourceType != 'groups' ||
              receipt.version != 1 ||
              receipt.requestId !=
                  canonicalAdminRequestId(
                    user.principalId ?? '',
                    pending.requestKey,
                  )) {
            throw const FormatException(
              'The original group receipt does not match.',
            );
          }
          store.clear(family: _family, resourceId: _resource);
          refreshCloudflareAdminData(ref, fence);
          widget.onDone();
          _message(
            pending.intent['visibility'] == 'public_approved'
                ? 'Public group created and activated'
                : 'The original group was created',
          );
        } else if (result['status'] == 'cancelled') {
          store.clear(family: _family, resourceId: _resource);
          _message(
            'The original request is cancelled. Reopen the form to create a group.',
          );
        } else {
          _message(
            'The result is unconfirmed. Check this request in Requests before creating another group.',
          );
        }
        return;
      }
      await createAdminPublicGroup(
        context,
        ref,
        canSubmit: current,
        onDone: widget.onDone,
        submit: (draft) async {
          if (!current()) return;
          final body = schema.canonical(platformPublicGroupBody(draft));
          final key = const Uuid().v4();
          store.retain(
            family: _family,
            resourceId: _resource,
            requestKey: key,
            permission: 'collections.create',
            intent: body,
            schema: schema,
          );
          try {
            await repository.operate(
              CloudflareOperation.createGroup,
              key: key,
              body: body,
            );
            if (!current()) return;
            store.clear(family: _family, resourceId: _resource);
            refreshCloudflareAdminData(ref, fence);
          } catch (_) {
            throw const AdminAccountException(
              'The result is unconfirmed. Check this request in Requests before creating another group.',
            );
          }
        },
      );
    } catch (error) {
      if (current()) {
        _message(
          error is AdminAccountException
              ? error.message
              : 'The original group request could not be confirmed. Check Requests.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    return PopupMenuButton<String>(
      key: _menu,
      tooltip: 'Create group',
      enabled: !_busy,
      child: FilledButton.icon(
        onPressed: _busy ? null : () => _menu.currentState?.showButtonMenu(),
        icon: const Icon(Icons.add),
        label: const Text('Create group'),
      ),
      onSelected: (value) {
        if (value == 'private') {
          widget.onCreatePrivate();
        } else if (value == 'public') {
          _public();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'private',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline),
            title: Text('Create private group'),
          ),
        ),
        if (_allowed(user))
          const PopupMenuItem(
            value: 'public',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.campaign_outlined),
              title: Text('Create public group'),
              subtitle: Text('Collect-sponsored group with a locked payee'),
            ),
          ),
      ],
    );
  }
}
