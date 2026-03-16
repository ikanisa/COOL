import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../shared/widgets/cool_card.dart';

/// A titled settings section containing a list of [ProfileSettingsRow]s.
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({
    required this.title,
    required this.rows,
    super.key,
  });

  final String title;
  final List<ProfileSettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.text2,
              ),
            ),
          ),
        ),
        CoolCard(
          backgroundColor: palette.surface,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(color: palette.border, height: 1, indent: 62),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ProfileFactItem {
  const ProfileFactItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
}

/// Compact summary card for passive account facts.
class ProfileFactsCard extends StatelessWidget {
  const ProfileFactsCard({required this.items, super.key});

  final List<ProfileFactItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      backgroundColor: palette.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ProfileFactTile(item: items[index]),
                  if (index < items.length - 1)
                    Divider(color: palette.border, height: 20),
                ],
              ],
            );
          }

          return Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(child: _ProfileFactTile(item: items[index])),
                if (index < items.length - 1)
                  Container(
                    width: 1,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: palette.border,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProfileFactTile extends StatelessWidget {
  const _ProfileFactTile({required this.item});

  final ProfileFactItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      label: '${item.label}: ${item.value}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.text3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: item.valueColor ?? palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row inside a [ProfileSettingsSection].
class ProfileSettingsRow extends StatelessWidget {
  const ProfileSettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.labelColor,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.showArrow = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final resolvedLabelColor = labelColor ?? palette.text;
    final resolvedValueColor = valueColor ?? palette.text2;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final shouldStackValue =
            trailing == null && value != null && constraints.maxWidth < 390;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: shouldStackValue
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? resolvedLabelColor.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: shouldStackValue
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: resolvedLabelColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: resolvedValueColor,
                              height: 1.35,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        label,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: resolvedLabelColor,
                        ),
                      ),
              ),
              if (trailing != null)
                trailing!
              else if (!shouldStackValue && value != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: resolvedValueColor,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (onTap != null && showArrow) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: EdgeInsets.only(top: shouldStackValue ? 2 : 0),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.text3,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    final semanticsLabel = value == null ? label : '$label: $value';
    if (onTap == null) {
      return Semantics(label: semanticsLabel, child: content);
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: 'Open $label',
      child: InkWell(
        onTap: onTap,
        splashColor: palette.accentGlow,
        highlightColor: Colors.transparent,
        child: content,
      ),
    );
  }
}

/// Collapsible entry point for lower-priority profile tools.
class ProfileSectionToggleCard extends StatelessWidget {
  const ProfileSectionToggleCard({
    required this.title,
    required this.subtitle,
    required this.isExpanded,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: '$title. $subtitle. ${isExpanded ?'Expanded' : 'Collapsed'}',
      hint: isExpanded
          ? 'Collapse section'
          : 'Expand section',
      child: ExcludeSemantics(
        child: CoolCard(
          backgroundColor: palette.surface,
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: palette.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: palette.text2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Danger-zone section with sign-out and delete-account rows.
class ProfileDangerZone extends StatelessWidget {
  const ProfileDangerZone({
    required this.onDeleteAccount,
    required this.onSignOut,
    super.key,
  });

  final VoidCallback onDeleteAccount;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    return ProfileSettingsSection(
      title: l10n.accountActionsTitle,
      rows: [
        ProfileSettingsRow(
          icon: Icons.logout_rounded,
          label: l10n.signOutAction,
          onTap: onSignOut,
        ),
        ProfileSettingsRow(
          icon: Icons.delete_outline_rounded,
          iconColor: palette.red,
          label: l10n.deleteAccountAction,
          labelColor: palette.red,
          onTap: onDeleteAccount,
          showArrow: false,
        ),
      ],
    );
  }
}

/// Adaptive toggle for push notifications.
class ProfileNotificationToggle extends StatelessWidget {
  const ProfileNotificationToggle({
    required this.value,
    required this.onChanged,
    this.isLoading = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      label: context.l10n.notificationsLabel,
      toggled: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(radius: 8),
            ),
            const SizedBox(width: 8),
          ],
          Switch.adaptive(
            value: value,
            onChanged: isLoading ? null : onChanged,
            activeTrackColor: palette.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// Theme mode selector shown inside the profile appearance sheet.
class ProfileAppearanceSheet extends StatelessWidget {
  const ProfileAppearanceSheet({
    required this.currentPreference,
    required this.onSelected,
    super.key,
  });

  final AppThemePreference currentPreference;
  final Future<void> Function(AppThemePreference preference) onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appearanceLabel,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 16),
        CoolCard(
          backgroundColor: palette.surface,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (
                var index = 0;
                index < AppThemePreference.values.length;
                index++
              ) ...[
                _ProfileAppearanceOption(
                  preference: AppThemePreference.values[index],
                  isSelected:
                      AppThemePreference.values[index] == currentPreference,
                  onTap: () => onSelected(AppThemePreference.values[index]),
                ),
                if (index < AppThemePreference.values.length - 1)
                  Divider(color: palette.border, height: 1, indent: 62),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAppearanceOption extends StatelessWidget {
  const _ProfileAppearanceOption({
    required this.preference,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool isSelected;
  final VoidCallback onTap;

  String _label(BuildContext context) {
    final l10n = context.l10n;
    return switch (preference) {
      AppThemePreference.system => l10n.appearanceSystemLabel,
      AppThemePreference.light => l10n.appearanceLightLabel,
      AppThemePreference.dark => l10n.appearanceDarkLabel,
    };
  }

  IconData _icon() {
    return switch (preference) {
      AppThemePreference.system => Icons.brightness_auto_rounded,
      AppThemePreference.light => Icons.light_mode_outlined,
      AppThemePreference.dark => Icons.dark_mode_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: _label(context),
      child: InkWell(
        onTap: onTap,
        splashColor: palette.accentGlow,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(_icon(), size: 18, color: palette.text2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label(context),
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? palette.accent : palette.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner shown when profile is incomplete.
class ProfileCompleteProfileBanner extends StatelessWidget {
  const ProfileCompleteProfileBanner({required this.phone, super.key});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.completeProfileTitle,
      hint: 'Complete your profile',
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.registerLocation(phone: phone)),
        child: ExcludeSemantics(
          child: CoolCard(
            backgroundColor: palette.surface,
            borderColor: palette.accent.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.accentGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.completeProfileTitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: palette.text3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
