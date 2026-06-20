import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class JoinGroupPortalScreen extends ConsumerStatefulWidget {
  const JoinGroupPortalScreen({super.key});

  @override
  ConsumerState<JoinGroupPortalScreen> createState() =>
      _JoinGroupPortalScreenState();
}

class _JoinGroupPortalScreenState extends ConsumerState<JoinGroupPortalScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Join group',
      subtitle: 'Enter a group code or scan a QR.',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: 'Join group',
            icon: CollectIcons.people,
            onPressed: _joinFromInput,
            expand: true,
          ),
          CollectButton(
            label: 'Scan QR',
            icon: CollectIcons.qr,
            onPressed: () => context.go('/groups/scan'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.qr,
          title: 'Join with a code.',
          message:
              'Paste a Collect link, enter a group code, or scan the group QR.',
          tone: CollectStatusTone.privacy,
          titleMaxLines: 2,
          messageMaxLines: 3,
          contentMaxWidth: 430,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.tonal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectTextInput(
                controller: _controller,
                label: 'Group code or link',
                helper: 'Example: st-michel-building-fund or a /c/ link.',
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _joinFromInput(),
              ),
              if (_error != null) ...[
                CollectSpacing.gap12,
                InfoSecurityBanner(
                  title: 'Code needed',
                  message: _error!,
                  tone: CollectStatusTone.warning,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _joinFromInput() {
    final slug = collectGroupSlugFromInput(_controller.text);
    if (slug.isEmpty) {
      setState(
        () => _error = 'Enter a group code or paste a Collect invite link.',
      );
      return;
    }
    setState(() => _error = null);
    context.go('/c/${Uri.encodeComponent(slug)}');
  }
}

class GroupLinkScreen extends ConsumerStatefulWidget {
  const GroupLinkScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<GroupLinkScreen> createState() => _GroupLinkScreenState();
}

class _GroupLinkScreenState extends ConsumerState<GroupLinkScreen> {
  late final Future<void> _openGroup = Future<void>.microtask(_joinAndOpen);

  Future<void> _joinAndOpen() async {
    if (_shouldOpenStoreFallback()) {
      await launchUrl(
        _storeFallbackUri(),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final profile = ref.read(collectRepositoryProvider).currentProfile;
    if (profile == null) {
      ref.read(pendingSharedGroupSlugProvider.notifier).state = widget.slug;
      if (!mounted) return;
      context.go('/onboarding');
      return;
    }
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .joinGroupBySlug(widget.slug);
    ref.read(pendingSharedGroupSlugProvider.notifier).state = null;
    if (!mounted) return;
    context.go('/groups/${collection.id}/joined');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _openGroup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ScreenScaffold(
            title: 'Group link',
            subtitle: widget.slug,
            children: [
              CollectBottomSheet(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InfoSecurityBanner(
                      title: 'Link failed',
                      message: snapshot.error.toString(),
                      tone: CollectStatusTone.danger,
                    ),
                    CollectSpacing.gap16,
                    CollectButton(
                      label: 'Groups',
                      icon: CollectIcons.collections,
                      onPressed: () => context.go('/groups'),
                      expand: true,
                    ),
                    CollectSpacing.gap12,
                    CollectButton(
                      label: 'Link help',
                      icon: CollectIcons.info,
                      onPressed: () => context.go('/share/invalid'),
                      variant: CollectButtonVariant.secondary,
                      expand: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

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

        return ScreenScaffold(
          title: 'Opening group',
          subtitle: widget.slug,
          children: const [
            CollectBottomSheet(
              child: LoadingStatePanel(
                title: 'Opening group',
                message: 'Joining the group.',
                icon: CollectIcons.qr,
                lines: 1,
              ),
            ),
          ],
        );
      },
    );
  }
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
