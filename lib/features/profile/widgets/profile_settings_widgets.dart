import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
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
                color: AppColors.text2,
              ),
            ),
          ),
        ),
        CoolCard(
          backgroundColor: AppColors.surface,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  const Divider(color: AppColors.border, height: 1, indent: 62),
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
    this.valueColor = AppColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;
}

/// Compact summary card for passive account facts.
class ProfileFactsCard extends StatelessWidget {
  const ProfileFactsCard({required this.items, super.key});

  final List<ProfileFactItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      backgroundColor: AppColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ProfileFactTile(item: items[index]),
                  if (index < items.length - 1)
                    const Divider(color: AppColors.border, height: 20),
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
                    color: AppColors.border,
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
                color: AppColors.text3,
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
                color: item.valueColor,
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
    this.valueColor = AppColors.text2,
    this.labelColor = AppColors.text,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.showArrow = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color valueColor;
  final Color labelColor;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
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
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? labelColor.withValues(alpha: 0.9),
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
                              color: labelColor,
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
                              color: valueColor,
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
                          color: labelColor,
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
                      color: valueColor,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (onTap != null && showArrow) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: EdgeInsets.only(top: shouldStackValue ? 2 : 0),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.text3,
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
      hint: 'Double tap to open $label',
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accentGlow,
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
    return Semantics(
      button: true,
      label: '$title. $subtitle. ${isExpanded ? 'Expanded' : 'Collapsed'}',
      hint: isExpanded
          ? 'Double tap to collapse this section'
          : 'Double tap to expand this section',
      child: ExcludeSemantics(
        child: CoolCard(
          backgroundColor: AppColors.surface,
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
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
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
                color: AppColors.text2,
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
          iconColor: AppColors.red,
          label: l10n.deleteAccountAction,
          labelColor: AppColors.red,
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
            activeTrackColor: AppColors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
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
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: '${l10n.completeProfileTitle}. ${l10n.completeProfileSubtitle}',
      hint: 'Double tap to complete your profile',
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.registerLocation(phone: phone)),
        child: ExcludeSemantics(
          child: CoolCard(
            backgroundColor: AppColors.surface,
            borderColor: AppColors.accent.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.completeProfileTitle,
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.completeProfileSubtitle,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.text2,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppColors.text3,
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
