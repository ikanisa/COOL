import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_icon_box.dart';
import '../../../shared/widgets/cool_list_tile.dart';
import '../../../shared/widgets/cool_stat_card.dart';
import '../../groups/group_flow_utils.dart';
import '../../groups/models/group.dart';
import '../models/home_dashboard_data.dart';
import 'home_shared.dart';

part 'home_communities_section.dart';
part 'home_operations_section.dart';
part 'home_sections_support.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.displayName,
    required this.avatarUrl,
    required this.onNotificationsTap,
    super.key,
  });

  final String displayName;
  final String? avatarUrl;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _ProfileAvatar(avatarUrl: avatarUrl),
            Positioned(
              right: -1,
              bottom: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: colors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadowColor.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: CoolSpace.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.home,
                style: context.coolText.mobiLabel(color: colors.secondaryText),
              ),
              const SizedBox(height: 2),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.coolText.headline(
                  Theme.of(context).textTheme.headlineLarge,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: CoolSpace.x3),
        Semantics(
          button: true,
          label: context.l10n.settings,
          child: _HomeIconButton(
            icon: CoolIcons.settingsGear,
            onTap: onNotificationsTap,
          ),
        ),
      ],
    );
  }
}

class HomeSavingsHeroCard extends StatelessWidget {
  const HomeSavingsHeroCard({
    required this.totalSavingsRwf,
    required this.monthlyNetChange,
    required this.onOpenSavings,
    this.isNewUser = false,
    super.key,
  });

  final int totalSavingsRwf;
  final int? monthlyNetChange;
  final VoidCallback onOpenSavings;
  final bool isNewUser;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Semantics(
      label:
          '${context.l10n.homeSavingsBalanceUpper}: ${fmtAmt(totalSavingsRwf)} RWF',
      button: true,
      child: CoolStatCard.accent(
        kicker: context.l10n.homeSavingsBalanceUpper,
        value: '${fmtAmt(totalSavingsRwf)} RWF',
        subtitleWidget: isNewUser
            ? Text(
                context.l10n.homeSavingsBalanceNewUserHint,
                style: context.coolText
                    .mobiLabel(color: colors.accentForeground)
                    .copyWith(fontWeight: FontWeight.w500),
              )
            : _MonthlyMovementPill(monthlyNetChange: monthlyNetChange),
        trailing: Icon(
          CoolIcons.forward,
          size: 18,
          color: colors.accentForeground,
        ),
        onTap: onOpenSavings,
      ),
    );
  }
}

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.coolText.headline(
              Theme.of(context).textTheme.titleLarge,
              color: colors.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class HomeSectionActionPill extends StatelessWidget {
  const HomeSectionActionPill({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: CoolSpace.x3,
            vertical: CoolSpace.x2,
          ),
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            style: context.coolText.mobiLabel(color: colors.accent),
          ),
        ),
      ),
    );
  }
}
