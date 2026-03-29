import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/rayon/models/rs_models.dart';
import 'cool_card.dart';

/// Fan-club card with join state and chapter stats.
class RsFanClubCard extends StatelessWidget {
  const RsFanClubCard({
    required this.club,
    required this.isJoined,
    required this.onJoinTap,
    this.onTap,
    super.key,
  });

  final RsFanClub club;
  final bool isJoined;
  final VoidCallback onJoinTap;
  final VoidCallback? onTap;

  static LinearGradient _bannerGradient(String region) {
    final lower = region.toLowerCase();
    if (lower.contains('kigali')) {
      return RsColors.rsMembershipGradient;
    }
    if (lower.contains('south') || lower.contains('huye')) {
      return RsColors.rsSupportGradient;
    }
    if (lower.contains('north') || lower.contains('musanze')) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[RsColors.rsRed, RsColors.rsNavyMid],
      );
    }
    return RsColors.rsCardGradient;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Semantics(
      label:
          '${club.name}. ${club.region}.'
          '${isJoined ? 'Joined' : 'Not joined'}. '
          '${club.memberCount} members.',
      excludeSemantics: true,
      child: CoolCard(
        onTap: onTap,
        gradient: RsColors.rsCardGradient,
        borderColor: isJoined
            ? RsColors.rsGold.withValues(alpha: 0.5)
            : RsColors.rsRedBorder,
        borderRadius: radii.lg,
        padding: EdgeInsets.zero,
        semanticsLabel: 'Open ${club.name} fan club',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: space.x1 + 2,
              decoration: BoxDecoration(
                gradient: _bannerGradient(club.region),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radii.lg),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(space.x4, space.x4, space.x4, 0),
              child: Row(
                children: [
                  Container(
                    width: CoolTapTargets.minimum,
                    height: CoolTapTargets.minimum,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: RsColors.rsRedGlow,
                      border: Border.all(
                        color: RsColors.rsRedBorder,
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 20,
                      color: RsColors.rsGoldLight,
                    ),
                  ),
                  SizedBox(width: space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          club.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.rayonCondensed(
                            theme.textTheme.titleLarge,
                            fontWeight: FontWeight.w900,
                            color: RsColors.rsWhite,
                            height: 0.95,
                          ),
                        ),
                        SizedBox(height: space.x1 / 2),
                        Text(
                          club.region,
                          style: text.rayon(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: RsColors.rsNavyPale,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: space.x2),
                  _JoinButton(isJoined: isJoined, onTap: onJoinTap),
                ],
              ),
            ),
            if (club.description.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(space.x4, space.x2, space.x4, 0),
                child: Text(
                  club.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.3,
                  ),
                ),
              ),
            SizedBox(height: space.x3),
            Container(
              decoration: BoxDecoration(
                color: colors.overlaySurface.withValues(alpha: 0.12),
                border: Border(top: BorderSide(color: colors.borderStrong)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: space.x3,
                vertical: space.x2 + 2,
              ),
              child: Row(
                children: [
                  _Stat(label: 'Members', value: '${club.memberCount}'),
                  _Divider(color: colors.borderStrong),
                  _Stat(label: 'Events', value: '${club.eventCount}'),
                  _Divider(color: colors.borderStrong),
                  _Stat(label: 'Rating', value: '${club.rating}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.isJoined, required this.onTap});

  final bool isJoined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final background = isJoined ? RsColors.rsRedGlow : RsColors.rsRed;
    final foreground = isJoined ? RsColors.rsNavyPale : RsColors.rsWhite;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isJoined ? null : onTap,
        borderRadius: BorderRadius.circular(radii.pill),
        child: AnimatedContainer(
          duration: CoolMotion.quick,
          constraints: const BoxConstraints(minHeight: CoolTapTargets.minimum),
          padding: EdgeInsets.symmetric(horizontal: space.x3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(radii.pill),
            border: Border.all(
              color: isJoined ? RsColors.rsRedBorder : RsColors.rsNavyMid,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            isJoined ? 'JOINED' : 'JOIN CLUB',
            style: text.rayonCondensed(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w800,
              color: foreground,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: color,
      margin: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: RsColors.rsGoldLight,
            ),
          ),
          const SizedBox(height: CoolSpace.x1 / 2),
          Text(
            label,
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}
