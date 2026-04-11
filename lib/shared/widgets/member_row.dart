import 'package:flutter/material.dart';

import '../../core/identity/public_user_identity.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/utils/money_formatters.dart';

/// A single-row widget displaying a group member with their avatar,
/// name / userId, admin badge (if applicable), and contribution amount.
class MemberRow extends StatelessWidget {
  const MemberRow({
    required this.userId,
    required this.contributionAmount,
    this.displayName,
    this.isAdmin = false,
    this.isAnonymous = false,
    super.key,
  });

  final String userId;
  final int contributionAmount;
  final String? displayName;
  final bool isAdmin;
  final bool isAnonymous;

  String get _initials {
    if (isAnonymous) return '?';
    final identity = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: userId,
    );
    return identity.substring(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final resolvedIdentity = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: userId,
    );
    final roleLabel = isAdmin ? ' Admin.' : '';

    return RepaintBoundary(
      child: Semantics(
        label:
            '$resolvedIdentity.$roleLabel'
            '${formatWholeMoneyAmount(contributionAmount)} RWF contributed.',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CoolSpace.x2),
          child: Row(
            children: [
              _Avatar(initials: _initials, isAnonymous: isAnonymous),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        resolvedIdentity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isAnonymous
                            ? text.mono(
                                theme.textTheme.bodySmall,
                                fontWeight: FontWeight.w500,
                                color: colors.secondaryText,
                              )
                            : theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.primaryText,
                              ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CoolSpace.x2,
                          vertical: CoolSpace.x1 / 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.chipSelectedBackground,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(CoolRadii.pill),
                          ),
                        ),
                        child: Text(
                          'Admin',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Text(
                formatWholeMoneyAmount(contributionAmount),
                style: text.mono(
                  theme.textTheme.titleSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.isAnonymous});

  final String initials;
  final bool isAnonymous;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final anonymousColor = colors.teamSurface;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isAnonymous
            ? LinearGradient(
                colors: [anonymousColor, anonymousColor.withValues(alpha: 0.6)],
              )
            : null,
        color: isAnonymous ? null : colors.chipSelectedBackground,
        border: Border.all(color: colors.borderStrong),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: text.mono(
          theme.textTheme.labelMedium,
          fontWeight: FontWeight.w800,
          color: isAnonymous ? colors.info : colors.accent,
        ),
      ),
    );
  }
}
