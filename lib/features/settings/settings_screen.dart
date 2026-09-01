import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final profile = state.currentProfile;
    final isInitialLoading = state.isLoading && profile == null;
    final settingsEntries = <Widget>[
      _SettingsTile(
        leading: CollectIcons.profile,
        title: 'Account details',
        onTap: () => context.go('/settings/account'),
      ),
      _SettingsTile(
        leading: CollectIcons.pending,
        title: 'Notifications',
        onTap: () => context.go('/settings/notifications'),
      ),
      if (profile?.isRwanda == true)
        _SettingsTile(
          leading: CollectIcons.momo,
          title: 'MoMo and USSD',
          onTap: () => context.go('/settings/permissions'),
        )
      else
        _SettingsTile(
          leading: Icons.account_balance_rounded,
          title: 'Diaspora bank transfer details',
          onTap: () => context.go('/settings/bank-transfer'),
        ),
      _SettingsTile(
        leading: CollectIcons.shield,
        title: 'App permissions',
        onTap: () => context.go('/settings/permissions'),
      ),
      _SettingsTile(
        leading: CollectIcons.palette,
        title: 'Appearance',
        onTap: () => context.go('/settings/appearance'),
      ),
      _SettingsTile(
        leading: CollectIcons.shield,
        title: 'Security',
        onTap: () => context.go('/settings/security'),
      ),
      _SettingsTile(
        leading: CollectIcons.privacy,
        title: 'Privacy policy',
        onTap: () => context.go('/settings/legal/privacy'),
      ),
      _SettingsTile(
        leading: CollectIcons.info,
        title: 'Terms',
        onTap: () => context.go('/settings/legal/terms'),
      ),
      _SettingsTile(
        leading: CollectIcons.support,
        title: 'Help',
        onTap: () => context.go('/settings/help'),
      ),
    ];
    return ScreenScaffold(
      title: 'Settings',
      showHeader: false,
      compact: true,
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading settings',
                message: 'Refreshing account and notification settings.',
                icon: CollectIcons.settings,
              ),
            ]
          : [
              _ProfileIdentityHeader(
                publicId: profile?.publicId ?? 'Collect',
                isComplete: profile?.isComplete ?? false,
                onTap: () => context.go('/settings/profile'),
              ),
              _SettingsCluster(children: settingsEntries),
              const SizedBox(height: 18),
            ],
    );
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({
    required this.publicId,
    required this.isComplete,
    required this.onTap,
  });

  final String publicId;
  final bool isComplete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final muted = CollectRuntimeTokens.chromeMutedForeground(colors);
    return Semantics(
      button: true,
      label: 'Edit profile $publicId',
      child: InkWell(
        onTap: onTap,
        borderRadius: CollectRadius.cardLargeBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: foreground.withValues(alpha: 0.18)),
                ),
                child: SizedBox.square(
                  dimension: 76,
                  child: Icon(
                    CollectIcons.profile,
                    color: foreground,
                    size: 32,
                  ),
                ),
              ),
              CollectSpacing.gap16,
              Text(
                publicId,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: foreground,
                  fontSize: CollectTypography.sizeMetric,
                  fontWeight: CollectTypography.weightBold,
                  height: CollectTypography.leadingTitle,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              CollectSpacing.gap8,
              Text(
                isComplete ? 'Collect profile' : 'Complete your profile',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontWeight: CollectTypography.weightMedium,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.leading, required this.title, this.onTap});

  final IconData leading;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: colors.transparent,
        child: InkWell(
          borderRadius: CollectRadius.mdBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x1,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              children: [
                _SettingsIconBadge(icon: leading),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: CollectTypography.weightSemibold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CollectSpacing.gapW8,
                onTap == null
                    ? const SizedBox.shrink()
                    : Icon(CollectIcons.chevron, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SizedBox.square(
      dimension: 28,
      child: Icon(icon, color: colors.textSecondary, size: 21),
    );
  }
}

class _SettingsCluster extends StatelessWidget {
  const _SettingsCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.normal,
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x3,
        vertical: CollectSpacing.x1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 40,
                color: colors.border.withValues(alpha: 0.46),
              ),
          ],
        ],
      ),
    );
  }
}
