import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/repositories/pending_shared_group_intent_store.dart';
import '../../core/supabase/supabase_module.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../profile/member_profile_gate.dart';

class GroupLinkScreen extends ConsumerStatefulWidget {
  const GroupLinkScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<GroupLinkScreen> createState() => _GroupLinkScreenState();
}

class _GroupLinkScreenState extends ConsumerState<GroupLinkScreen> {
  late Future<void> _prepareInvitation;
  PendingSharedGroupIntent? _invitation;
  bool _joining = false;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _prepareInvitation = Future<void>.microtask(_prepare);
  }

  @override
  void didUpdateWidget(covariant GroupLinkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug == widget.slug) return;
    _invitation = null;
    _joinError = null;
    _joining = false;
    _prepareInvitation = Future<void>.microtask(_prepare);
  }

  Future<void> _prepare() async {
    if (_shouldOpenStoreFallback()) return;
    final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
    final ownerId = ref.read(collectAuthenticatedUserIdProvider);
    final existing = await pendingIntent.currentRecord();
    PendingSharedGroupIntent invitation;
    if (existing?.slug == widget.slug) {
      if (existing!.ownerUserId != null && existing.ownerUserId != ownerId) {
        throw StateError('Invitation belongs to a different account.');
      }
      if (ownerId == null) {
        invitation = existing;
      } else {
        final current = await pendingIntent.currentRecordForOwner(ownerId);
        if (current == null) {
          throw StateError('Invitation expired or was replaced.');
        }
        invitation = current;
      }
    } else {
      invitation = await pendingIntent.retainRecord(
        widget.slug,
        ownerUserId: ownerId,
      );
    }
    if (!mounted) return;
    _invitation = invitation;
  }

  void _retryPrepare() {
    setState(() {
      _prepareInvitation = Future<void>.microtask(_prepare);
    });
  }

  Future<void> _joinAndOpen() async {
    if (_joining) return;
    final ownerId = ref.read(collectAuthenticatedUserIdProvider);
    if (ownerId == null) {
      context.go('/auth');
      return;
    }
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
      final expected = _invitation;
      final current = await pendingIntent.currentRecordForOwner(ownerId);
      if (expected?.ownerUserId != null && expected!.ownerUserId != ownerId) {
        throw StateError('Account changed. Open the link again.');
      }
      if (expected != null &&
          current != null &&
          current.slug == widget.slug &&
          current.intentId != expected.intentId) {
        setState(() {
          _invitation = current;
          _joinError =
              'This invitation was refreshed. Review it and choose Join again.';
        });
        return;
      }
      if (expected == null ||
          current == null ||
          current.intentId != expected.intentId ||
          current.slug != widget.slug) {
        throw StateError('Invitation changed. Open the latest link again.');
      }
      if (!mounted) return;
      await requireMemberProfileReady(context, ref);
      if (!mounted) return;
      if (ref.read(collectAuthenticatedUserIdProvider) != ownerId ||
          ref.read(collectRepositoryProvider).currentProfile?.id != ownerId) {
        throw StateError('Account changed. Open the link again.');
      }
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(current.slug);
      if (!mounted) return;
      if (ref.read(collectAuthenticatedUserIdProvider) != ownerId ||
          ref.read(collectRepositoryProvider).currentProfile?.id != ownerId) {
        throw StateError('Account changed. Open the link again.');
      }
      // A later invitation can replace this record while the server joins.
      // Keep that newer record, but show the successful membership here.
      await pendingIntent.clearIfMatchesRecord(current);
      if (!mounted) return;
      if (ref.read(collectAuthenticatedUserIdProvider) != ownerId) {
        throw StateError('Account changed. Open the link again.');
      }
      context.go('/groups/${collection.id}');
    } catch (error) {
      if (mounted) setState(() => _joinError = _safeGroupLinkError(error));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldOpenStoreFallback()) {
      return ScreenScaffold(
        title: 'Install Collect',
        subtitle: widget.slug,
        children: [
          CollectBottomSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MinimalStatePanel(
                  icon: CollectIcons.download,
                  title: 'Install Collect to join.',
                  message:
                      'After installing, open this group link again to finish onboarding and join.',
                  tone: CollectStatusTone.info,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: 'Open store',
                  icon: CollectIcons.download,
                  onPressed: () => launchUrl(
                    _storeFallbackUri(),
                    mode: LaunchMode.externalApplication,
                  ),
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return FutureBuilder<void>(
      future: _prepareInvitation,
      builder: (context, snapshot) {
        final value = _groupLinkSnapshotValue(snapshot);
        return ScreenScaffold(
          title: 'Group invitation',
          subtitle: widget.slug,
          children: [
            CollectBottomSheet(
              child: CollectAsyncStateView<void>(
                value: value,
                loadingTitle: 'Checking invitation',
                loadingMessage: 'Saving this link on your device.',
                loadingIcon: CollectIcons.qr,
                errorTitle: 'Link failed',
                errorMessage: _safeGroupLinkError(snapshot.error),
                onRetry: _retryPrepare,
                data: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MinimalStatePanel(
                      icon: CollectIcons.qr,
                      title: 'Review this group invitation',
                      message: 'Choose Join to add this group to your account.',
                      tone: CollectStatusTone.info,
                    ),
                    if (_joinError != null) ...[
                      CollectSpacing.gap16,
                      MinimalStatePanel(
                        icon: CollectIcons.warning,
                        title: 'Could not join',
                        message: _joinError!,
                        tone: CollectStatusTone.warning,
                      ),
                    ],
                    CollectSpacing.gap16,
                    CollectButton(
                      label: _joining
                          ? 'Joining group'
                          : ref.read(collectAuthenticatedUserIdProvider) == null
                          ? 'Sign in to join'
                          : 'Join group',
                      icon: CollectIcons.qr,
                      onPressed: _joining
                          ? null
                          : () => unawaited(_joinAndOpen()),
                      expand: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _safeGroupLinkError(Object? error) {
  if (error is FormatException) return error.message;
  final message = error?.toString().toLowerCase() ?? '';
  if (message.contains('different account') ||
      message.contains('account changed')) {
    return 'This invitation was opened with another account. Open the link again after switching accounts.';
  }
  if (message.contains('invitation changed')) {
    return 'A newer invitation is ready. Open the latest link again.';
  }
  if (message.contains('removed by a group admin')) {
    return 'Your membership was removed. Contact a group admin if this needs review.';
  }
  if (message.contains('archived')) {
    return 'This group is archived and no longer accepts invitations.';
  }
  if (message.contains('invalid') || message.contains('expired')) {
    return 'This invitation is invalid or was replaced. Ask a group admin for the current link.';
  }
  return 'Try again when the connection is stable. The invitation stays on this device for 24 hours.';
}

AsyncValue<void> _groupLinkSnapshotValue(AsyncSnapshot<void> snapshot) {
  if (snapshot.connectionState != ConnectionState.done) {
    return const AsyncLoading<void>();
  }
  if (snapshot.hasError) {
    return AsyncError<void>(
      snapshot.error!,
      snapshot.stackTrace ?? StackTrace.current,
    );
  }
  return const AsyncData<void>(null);
}

bool _shouldOpenStoreFallback() {
  return kIsWeb && Uri.base.host == 'collect.ikanisa.com';
}

Uri _storeFallbackUri() {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return Uri.parse(collectAppleAppStoreUrl);
  }
  return Uri.parse(collectGooglePlayUrl);
}

String collectGroupSlugFromInput(String input, {Uri? trustedPublicOrigin}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final rawCode = normalizePendingSharedGroupSlug(trimmed);
  if (rawCode != null) return rawCode;
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      collectGroupLinkHasAlternateTarget(uri)) {
    return '';
  }
  final canonical = collectAppLinkTargetFromUri(uri);
  if (canonical?.kind == CollectAppLinkKind.group) {
    return canonical!.value!;
  }
  final origin = trustedPublicOrigin;
  if (origin == null ||
      uri.scheme != 'https' ||
      uri.host.toLowerCase() != origin.host.toLowerCase() ||
      uri.port != origin.port ||
      uri.userInfo.isNotEmpty) {
    return '';
  }
  final prefix = origin.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.length != prefix.length + 2 ||
      !listEquals(segments.take(prefix.length).toList(), prefix) ||
      segments[prefix.length] != 'c') {
    return '';
  }
  return normalizePendingSharedGroupSlug(segments.last) ?? '';
}
