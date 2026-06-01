import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  final _code = TextEditingController();
  String? _error;
  bool _joining = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Join group',
      subtitle: 'Code, link, or QR.',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.qr,
          title: 'Enter a Collect group code.',
          message:
              'Paste a shared Collect link or enter the group code. Receiver MoMo details stay inside the contribution review step.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _code,
                decoration: collectInputDecoration(
                  context,
                  label: 'Group code or link',
                  helper: 'Example: st-michel-building-fund or a /c/ link.',
                ),
              ),
              if (_error != null) ...[
                CollectSpacing.gap12,
                InfoSecurityBanner(
                  title: 'Could not join',
                  message: _error!,
                  tone: CollectStatusTone.danger,
                ),
              ],
              CollectSpacing.gap16,
              CollectButton(
                label: _joining ? 'Joining' : 'Join group',
                icon: CollectIcons.arrowForward,
                onPressed: _joining ? null : _join,
                expand: true,
              ),
              CollectSpacing.gap12,
              CollectButton(
                label: 'Scan QR code',
                icon: CollectIcons.qr,
                onPressed: () => setState(() {
                  _error =
                      'QR scanning is not enabled in this build. Use the group link or code.';
                }),
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _join() async {
    final slug = _slugFromInput(_code.text);
    if (slug.isEmpty) {
      setState(() => _error = 'Enter a group code or Collect link.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(slug);
      if (!mounted) return;
      context.go('/groups/${collection.id}/joined');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = error.toString();
      });
    }
  }
}

class GroupLinkScreen extends ConsumerStatefulWidget {
  const GroupLinkScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<GroupLinkScreen> createState() => _GroupLinkScreenState();
}

class _GroupLinkScreenState extends ConsumerState<GroupLinkScreen> {
  late final Future<void> _openGroup = _joinAndOpen();

  Future<void> _joinAndOpen() async {
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .joinGroupBySlug(widget.slug);
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
                      onPressed: () => context.go('/c/${widget.slug}/invalid'),
                      variant: CollectButtonVariant.secondary,
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
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ],
        );
      },
    );
  }
}

String _slugFromInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final segments = uri.pathSegments;
    final cIndex = segments.indexOf('c');
    if (cIndex != -1 && cIndex + 1 < segments.length) {
      return segments[cIndex + 1];
    }
  }
  return trimmed.replaceFirst(RegExp(r'^/c/'), '').trim();
}
