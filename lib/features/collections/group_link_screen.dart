import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class GroupLinkScreen extends ConsumerStatefulWidget {
  const GroupLinkScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<GroupLinkScreen> createState() => _GroupLinkScreenState();
}

class _GroupLinkScreenState extends ConsumerState<GroupLinkScreen> {
  late Future<void> _openGroup;

  @override
  void initState() {
    super.initState();
    _openGroup = Future<void>.microtask(_joinAndOpen);
  }

  Future<void> _joinAndOpen() async {
    if (_shouldOpenStoreFallback()) {
      await launchUrl(
        _storeFallbackUri(),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
    final slug = await pendingIntent.retain(widget.slug);
    final profile = ref.read(collectRepositoryProvider).currentProfile;
    if (profile == null) {
      if (!mounted) return;
      context.go('/auth');
      return;
    }
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .joinGroupBySlug(slug);
    final cleared = await pendingIntent.clearIfMatches(slug);
    if (!mounted) return;
    if (!cleared) return;
    context.go('/groups/${collection.id}');
  }

  void _retry() {
    setState(() {
      _openGroup = Future<void>.microtask(_joinAndOpen);
    });
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
      future: _openGroup,
      builder: (context, snapshot) {
        final value = _groupLinkSnapshotValue(snapshot);
        final hasError = snapshot.hasError;
        return ScreenScaffold(
          title: hasError ? 'Group link' : 'Opening group',
          subtitle: widget.slug,
          children: [
            CollectBottomSheet(
              child: CollectAsyncStateView<void>(
                value: value,
                loadingTitle: 'Opening group',
                loadingMessage: 'Joining the group.',
                loadingIcon: CollectIcons.qr,
                errorTitle: 'Link failed',
                errorMessage:
                    snapshot.error?.toString() ??
                    'Try again from Groups when the connection is stable.',
                onRetry: _retry,
                data: (context, _) => const MinimalStatePanel(
                  icon: CollectIcons.qr,
                  title: 'Opening group',
                  message: 'Taking you to the group.',
                  tone: CollectStatusTone.info,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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
    return Uri.parse('https://apps.apple.com/search?term=Collect%20Ikanisa');
  }
  return Uri.parse(
    'https://play.google.com/store/apps/details?id=app.cool.mobile',
  );
}

String collectGroupSlugFromInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final fragmentUri = Uri.tryParse(uri.fragment);
    final candidates = [
      uri.queryParameters['code'],
      uri.queryParameters['slug'],
      uri.queryParameters['group'],
      if (fragmentUri != null) ..._slugSegments(fragmentUri.pathSegments),
      ..._slugSegments(uri.pathSegments),
    ];
    for (final candidate in candidates) {
      final clean = candidate?.trim();
      if (clean != null && clean.isNotEmpty) {
        return Uri.decodeComponent(clean);
      }
    }
  }
  return trimmed
      .replaceFirst(RegExp(r'^/?c/'), '')
      .replaceFirst(RegExp(r'^/?groups/'), '')
      .trim();
}

List<String?> _slugSegments(List<String> segments) {
  final cIndex = segments.indexOf('c');
  final groupIndex = segments.indexOf('groups');
  return [
    if (cIndex != -1 && cIndex + 1 < segments.length) segments[cIndex + 1],
    if (groupIndex != -1 && groupIndex + 1 < segments.length)
      segments[groupIndex + 1],
  ];
}
