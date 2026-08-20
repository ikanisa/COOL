import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_theme_controller.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../status/native_permission_sheets.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final preferences = state.notificationPreferences;
    return ScreenScaffold(
      title: 'Notifications',
      showHeader: false,
      compact: true,
      topChrome: const _SettingsSubpageHeader(
        title: 'Notifications',
        icon: CollectIcons.pending,
      ),
      children: [
        if (_saving)
          Semantics(
            liveRegion: true,
            label: 'Saving notification preferences',
            child: const LinearProgressIndicator(),
          ),
        _SettingsOptionPanel(
          children: [
            _SettingsSwitchRow(
              title: 'Contribution confirmations',
              subtitle: 'Reconciled bank contributions and ledger updates.',
              value: preferences.contributionConfirmations,
              onChanged: state.currentProfile == null || _saving
                  ? null
                  : (value) => _save(
                      preferences.copyWith(contributionConfirmations: value),
                    ),
            ),
            _SettingsSwitchRow(
              title: 'Payment reminders',
              subtitle: 'Pending contribution reminders before expiry.',
              value: preferences.paymentReminders,
              onChanged: state.currentProfile == null || _saving
                  ? null
                  : (value) =>
                        _save(preferences.copyWith(paymentReminders: value)),
            ),
            _SettingsSwitchRow(
              title: 'Group updates',
              subtitle: 'Membership and group-management changes.',
              value: preferences.groupUpdates,
              onChanged: state.currentProfile == null || _saving
                  ? null
                  : (value) => _save(preferences.copyWith(groupUpdates: value)),
            ),
            _SettingsSwitchRow(
              title: 'Security notices',
              subtitle: 'Important account and privacy alerts.',
              value: preferences.securityNotices,
              onChanged: state.currentProfile == null || _saving
                  ? null
                  : (value) =>
                        _save(preferences.copyWith(securityNotices: value)),
            ),
          ],
        ),
        CollectButton(
          label: 'Review phone permission',
          icon: CollectIcons.settings,
          variant: CollectButtonVariant.secondary,
          onPressed: () => showNotificationSettingsSheet(context, ref),
          expand: true,
        ),
      ],
    );
  }

  Future<void> _save(NotificationPreferences preferences) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .updateNotificationPreferences(preferences);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save notification preferences. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(collectThemeModeProvider);
    return ScreenScaffold(
      title: 'Appearance',
      showHeader: false,
      compact: true,
      topChrome: const _SettingsSubpageHeader(
        title: 'Appearance',
        icon: CollectIcons.palette,
      ),
      children: [
        _AppearancePreview(mode: mode),
        const SectionHeader(title: 'Mode'),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final choices = [
              _AppearanceModeChoice(
                label: 'Dark',
                icon: Icons.dark_mode_rounded,
                selected: mode == ThemeMode.dark,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.dark),
                ),
              ),
              _AppearanceModeChoice(
                label: 'Light',
                icon: Icons.light_mode_rounded,
                selected: mode == ThemeMode.light,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.light),
                ),
              ),
              _AppearanceModeChoice(
                label: 'System',
                icon: Icons.devices_rounded,
                selected: mode == ThemeMode.system,
                onTap: () => unawaited(
                  ref
                      .read(collectThemeModeProvider.notifier)
                      .setMode(ThemeMode.system),
                ),
              ),
            ];
            if (constraints.maxWidth < 330 || largeText) {
              return Column(
                children: [
                  for (final choice in choices) ...[
                    choice,
                    if (choice != choices.last) CollectSpacing.gap12,
                  ],
                ],
              );
            }
            return Row(
              children: List.generate(choices.length * 2 - 1, (index) {
                if (index.isOdd) return CollectSpacing.gapW12;
                return Expanded(child: choices[index ~/ 2]);
              }),
            );
          },
        ),
        const InfoSecurityBanner(
          title: 'Saved on this device',
          message:
              'Your selected mode stays active the next time Collect opens.',
          tone: CollectStatusTone.privacy,
        ),
      ],
    );
  }
}

class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Security',
      showHeader: false,
      compact: true,
      topChrome: const _SettingsSubpageHeader(
        title: 'Security',
        icon: CollectIcons.shield,
        showHeading: false,
      ),
      hero: const CollectScreenHero(
        title: 'Security',
        subtitle: 'Account, payment, and privacy safeguards',
        icon: CollectIcons.shield,
      ),
      children: [
        const InfoSecurityBanner(
          title: 'Approve transfers in your bank app',
          message:
              'Collect never asks for a bank password, PIN, OTP, or payment credential.',
          tone: CollectStatusTone.warning,
        ),
        _SettingsOptionPanel(
          children: [
            _SettingsLinkRow(
              icon: CollectIcons.lock,
              title: 'Session and profile',
              subtitle: 'Review account details, Collect ID, and sign out.',
              onTap: () => context.go('/settings/account'),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.bank,
              title: 'Contribution verification',
              subtitle:
                  'Only statement-reconciled bank receipts reach ledgers.',
              onTap: () => context.go('/activity'),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Bank detail privacy',
              subtitle:
                  'Approved beneficiary details are visible only to signed-in members.',
              onTap: () => context.go('/settings/legal/privacy'),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.error,
              title: 'Delete data',
              subtitle: 'Create an auditable account deletion request.',
              onTap: () => context.go('/settings/account/delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class HelpSettingsScreen extends ConsumerWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtimeConfig = ref.watch(collectRuntimeConfigProvider);
    return ScreenScaffold(
      title: 'Help',
      showHeader: false,
      compact: true,
      topChrome: const _SettingsSubpageHeader(
        title: 'Help',
        icon: CollectIcons.support,
      ),
      children: [
        const SectionHeader(title: 'Common problems'),
        _SettingsOptionPanel(
          children: [
            _SettingsLinkRow(
              icon: CollectIcons.lock,
              title: 'Sign-in or code problem',
              subtitle: 'Get help when a code is late, expired, or rejected.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.pending,
              title: 'Contribution issue',
              subtitle:
                  'Ask about a pending, missing, duplicate, or wrong contribution.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.qr,
              title: 'QR, sharing, or joining',
              subtitle: 'Get help finding, joining, scanning, or sharing.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.people,
              title: 'Membership or owner issue',
              subtitle: 'Get help with group access, roles, or ownership.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Privacy or deletion request',
              subtitle: 'Review privacy or create an auditable request.',
              onTap: () => context.go('/settings/account/delete'),
            ),
          ],
        ),
        const SectionHeader(title: 'Contact and policies'),
        _SettingsOptionPanel(
          children: [
            _SettingsLinkRow(
              icon: CollectIcons.support,
              title: 'WhatsApp support',
              subtitle: 'Contact IKANISA through the configured support line.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Privacy policy',
              subtitle: 'Understand how Collect handles customer data.',
              onTap: () => context.go('/settings/legal/privacy'),
            ),
            _SettingsLinkRow(
              icon: CollectIcons.info,
              title: 'Terms',
              subtitle: 'Review the rules for using Collect.',
              onTap: () => context.go('/settings/legal/terms'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSubpageHeader extends StatelessWidget {
  const _SettingsSubpageHeader({
    required this.title,
    required this.icon,
    this.showHeading = true,
  });

  final String title;
  final IconData icon;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final control = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    return Semantics(
      container: true,
      header: true,
      label: title,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              backgroundColor: control,
              foregroundColor: foreground,
              side: BorderSide(color: border),
            ),
          ),
          if (showHeading) ...[
            CollectSpacing.gapW12,
            Icon(icon, color: foreground, size: 22),
            CollectSpacing.gapW8,
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: CollectTypography.weightBold,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _SettingsOptionPanel extends StatelessWidget {
  const _SettingsOptionPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x3),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 52,
                color: colors.border.withValues(alpha: 0.48),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: CollectTypography.weightSemibold,
                      ),
                    ),
                    CollectSpacing.gap4,
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.collectColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLinkRow extends StatelessWidget {
  const _SettingsLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CollectListTile(
      leading: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final effectiveBrightness = switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => Theme.of(context).brightness,
    };
    final previewColors = effectiveBrightness == Brightness.dark
        ? CollectColors.dark
        : CollectColors.light;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      image: true,
      label: '${_appearanceModeLabel(mode)} Collect home preview',
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: Container(
            key: const ValueKey('appearance-live-preview'),
            height: 356,
            padding: const EdgeInsets.all(CollectSpacing.x4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: previewColors.canvas,
              borderRadius: CollectRadius.cardLargeBorder,
              border: Border.all(color: previewColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      padding: const EdgeInsets.all(CollectSpacing.x1),
                      decoration: BoxDecoration(
                        color: previewColors.surfaceRaised,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        CollectRuntimeAssets.officialLogo,
                        fit: BoxFit.contain,
                      ),
                    ),
                    CollectSpacing.gapW8,
                    Expanded(
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CollectSpacing.x3,
                        ),
                        decoration: BoxDecoration(
                          color: previewColors.surfaceReadable,
                          borderRadius: CollectRadius.pillBorder,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CollectIcons.search,
                              size: 14,
                              color: previewColors.textSecondary,
                            ),
                            CollectSpacing.gapW4,
                            Text(
                              'Search',
                              style: textTheme.labelSmall?.copyWith(
                                color: previewColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    CollectSpacing.gapW8,
                    _AppearancePreviewCircle(
                      icon: CollectIcons.activity,
                      colors: previewColors,
                    ),
                  ],
                ),
                CollectSpacing.gap20,
                Text(
                  'Total collected',
                  style: textTheme.labelSmall?.copyWith(
                    color: previewColors.textSecondary,
                  ),
                ),
                Text(
                  'RWF 35,000',
                  style: textTheme.headlineMedium?.copyWith(
                    color: previewColors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                CollectSpacing.gap16,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.donate,
                        label: 'Contribute',
                        colors: previewColors,
                      ),
                    ),
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.people,
                        label: 'Groups',
                        colors: previewColors,
                      ),
                    ),
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.qr,
                        label: 'QR',
                        colors: previewColors,
                      ),
                    ),
                    Expanded(
                      child: _AppearancePreviewAction(
                        icon: CollectIcons.settings,
                        label: 'More',
                        colors: previewColors,
                      ),
                    ),
                  ],
                ),
                CollectSpacing.gap16,
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CollectSpacing.x3),
                    decoration: BoxDecoration(
                      color: previewColors.surfaceReadable,
                      borderRadius: CollectRadius.cardBorder,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent activity',
                          style: textTheme.titleSmall?.copyWith(
                            color: previewColors.textPrimary,
                            fontWeight: CollectTypography.weightBold,
                          ),
                        ),
                        const Spacer(),
                        _AppearancePreviewLedgerRow(
                          amount: 'RWF 10,000',
                          colors: previewColors,
                        ),
                        Divider(color: previewColors.borderSoft, height: 12),
                        _AppearancePreviewLedgerRow(
                          amount: 'RWF 25,000',
                          colors: previewColors,
                        ),
                      ],
                    ),
                  ),
                ),
                CollectSpacing.gap12,
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x3,
                  ),
                  decoration: BoxDecoration(
                    color: effectiveBrightness == Brightness.dark
                        ? CollectColors.referenceChromeBlack
                        : previewColors.surfaceRaised,
                    borderRadius: CollectRadius.controlBorder,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final icon in const [
                        CollectIcons.home,
                        CollectIcons.people,
                        CollectIcons.donate,
                        CollectIcons.activity,
                        CollectIcons.profile,
                      ])
                        Icon(
                          icon,
                          size: 16,
                          color: icon == CollectIcons.home
                              ? previewColors.info
                              : previewColors.textMuted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearancePreviewCircle extends StatelessWidget {
  const _AppearancePreviewCircle({required this.icon, required this.colors});

  final IconData icon;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: colors.textPrimary),
    );
  }
}

class _AppearancePreviewAction extends StatelessWidget {
  const _AppearancePreviewAction({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _AppearancePreviewCircle(icon: icon, colors: colors),
        CollectSpacing.gap4,
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _AppearancePreviewLedgerRow extends StatelessWidget {
  const _AppearancePreviewLedgerRow({
    required this.amount,
    required this.colors,
  });

  final String amount;
  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(CollectIcons.check, size: 14, color: colors.success),
        CollectSpacing.gapW8,
        Expanded(
          child: Text(
            '038491',
            style: textTheme.labelSmall?.copyWith(color: colors.textPrimary),
          ),
        ),
        Text(
          amount,
          style: textTheme.labelSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
      ],
    );
  }
}

class _AppearanceModeChoice extends StatelessWidget {
  const _AppearanceModeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      child: InkWell(
        onTap: onTap,
        borderRadius: CollectRadius.cardBorder,
        child: AnimatedContainer(
          duration: CollectMotion.duration(context, CollectMotion.medium),
          constraints: const BoxConstraints(minHeight: CollectSpacing.target),
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x2,
            vertical: CollectSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.infoContainer : colors.surfaceReadable,
            borderRadius: CollectRadius.cardBorder,
            border: Border.all(
              color: selected ? colors.focusRing : colors.borderSoft,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? colors.info : colors.textSecondary,
                size: 20,
              ),
              CollectSpacing.gapW4,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: selected
                        ? CollectTypography.weightBold
                        : CollectTypography.weightMedium,
                  ),
                ),
              ),
              if (selected)
                Icon(CollectIcons.check, color: colors.success, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String _appearanceModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'Dark',
  ThemeMode.light => 'Light',
  ThemeMode.system => 'System',
};
