import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_theme_controller.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final paymentIntents = ref.watch(
      collectRepositoryProvider.select((state) => state.paymentIntents),
    );
    final systemEntries = _visibleEntries([
      _SettingsEntry(
        keywords: 'notifications alerts updates',
        child: _SettingsTile(
          leading: CollectIcons.pending,
          title: 'Notifications',
          onTap: () => context.go('/notifications'),
        ),
      ),
      const _SettingsEntry(
        keywords: 'dark mode theme appearance',
        child: _ThemeModeTile(),
      ),
    ]);
    final accountEntries = _visibleEntries([
      _SettingsEntry(
        keywords: 'account profile momo sign out delete data',
        child: _SettingsTile(
          leading: CollectIcons.profile,
          title: 'Account',
          onTap: () => context.go('/settings/account'),
        ),
      ),
    ]);
    final supportEntries = _visibleEntries([
      const _SettingsEntry(
        keywords: 'help support whatsapp',
        child: _SettingsTile(
          leading: CollectIcons.support,
          title: 'Help',
          onTap: openCollectWhatsAppSupport,
        ),
      ),
      _SettingsEntry(
        keywords: 'terms conditions legal',
        child: _SettingsTile(
          leading: CollectIcons.info,
          title: 'Terms',
          onTap: () => context.go('/settings/legal/terms'),
        ),
      ),
      _SettingsEntry(
        keywords: 'privacy policy data legal',
        child: _SettingsTile(
          leading: CollectIcons.privacy,
          title: 'Privacy policy',
          onTap: () => context.go('/settings/legal/privacy'),
        ),
      ),
      if (kDebugMode)
        _SettingsEntry(
          keywords: 'design system tokens components',
          child: _SettingsTile(
            leading: CollectIcons.palette,
            title: 'Design system',
            onTap: () => context.go('/dev/design-system'),
          ),
        ),
    ]);
    final hasResults =
        systemEntries.isNotEmpty ||
        accountEntries.isNotEmpty ||
        supportEntries.isNotEmpty;
    return ScreenScaffold(
      title: 'Settings',
      showHeader: false,
      compact: true,
      persistentPill: CollectTopChrome(
        avatarLabel: profile?.publicId,
        searchController: _search,
        searchLabel: 'Search settings',
        onSearchChanged: (value) => setState(() => _query = value),
        onAvatarTap: () => context.go('/settings/profile'),
        hasUnread: paymentIntents.isNotEmpty,
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.pending,
            tooltip: 'Notifications',
            hasBadge: paymentIntents.isNotEmpty,
            onPressed: () => context.go('/notifications'),
          ),
          CollectTopChromeAction(
            icon: CollectIcons.profile,
            tooltip: 'Account',
            onPressed: () => context.go('/settings/account'),
          ),
        ],
      ),
      children: [
        _SettingsProfileCard(publicId: profile?.publicId ?? ''),
        if (systemEntries.isNotEmpty)
          _SettingsCluster(
            tone: CollectStatusTone.privacy,
            children: systemEntries.map((entry) => entry.child).toList(),
          ),
        if (accountEntries.isNotEmpty)
          _SettingsCluster(
            tone: CollectStatusTone.info,
            children: accountEntries.map((entry) => entry.child).toList(),
          ),
        if (supportEntries.isNotEmpty)
          _SettingsCluster(
            tone: CollectStatusTone.success,
            children: supportEntries.map((entry) => entry.child).toList(),
          ),
        if (!hasResults)
          const EmptyIllustrationState(
            icon: CollectIcons.search,
            title: 'No settings found',
            message: 'Try account, privacy, notifications, or help.',
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  List<_SettingsEntry> _visibleEntries(List<_SettingsEntry> entries) {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return entries;
    return [
      for (final entry in entries)
        if (entry.matches(normalized)) entry,
    ];
  }
}

class _SettingsEntry {
  const _SettingsEntry({required this.keywords, required this.child});

  final String keywords;
  final Widget child;

  bool matches(String query) => keywords.toLowerCase().contains(query);
}

class _SettingsProfileCard extends StatelessWidget {
  const _SettingsProfileCard({required this.publicId});

  final String publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x4,
        vertical: CollectSpacing.x3,
      ),
      child: Row(
        children: [
          const _SettingsIconBadge(icon: CollectIcons.profile),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
                height: 0.96,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(collectThemeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    return _SettingsTile(
      leading: CollectIcons.palette,
      title: 'Dark mode',
      onTap: () => unawaited(
        ref.read(collectThemeModeProvider.notifier).setDarkMode(!isDark),
      ),
      trailing: Switch.adaptive(
        value: isDark,
        onChanged: (value) => unawaited(
          ref.read(collectThemeModeProvider.notifier).setDarkMode(value),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData leading;
  final String title;
  final Widget? trailing;
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
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CollectSpacing.gapW8,
                trailing ??
                    (onTap == null
                        ? const SizedBox.shrink()
                        : Icon(CollectIcons.chevron, color: colors.textMuted)),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        shape: BoxShape.circle,
        border: Border.all(color: colors.glassBorder),
      ),
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, color: colors.textSecondary, size: 22),
      ),
    );
  }
}

class _SettingsCluster extends StatelessWidget {
  const _SettingsCluster({required this.children, required this.tone});

  final List<Widget> children;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = colors.statusForeground(tone);
    return CollectCard(
      emphasis: CollectCardEmphasis.tonal,
      accentColor: accent,
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x3,
        vertical: CollectSpacing.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
