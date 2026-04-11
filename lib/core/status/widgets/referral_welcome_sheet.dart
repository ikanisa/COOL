import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../core/l10n/l10n.dart';

class ReferralWelcomeSheet extends StatelessWidget {
  const ReferralWelcomeSheet({
    required this.inviterName,
    required this.onAccept,
    super.key,
  });

  final String inviterName;
  final VoidCallback onAccept;

  static Future<void> show(
    BuildContext context, {
    required String inviterName,
    required VoidCallback onAccept,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ReferralWelcomeSheet(inviterName: inviterName, onAccept: onAccept),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(space.x6, space.x5, space.x6, space.x10),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: space.x8),
          Text('🤝', style: context.coolText.display(null).copyWith(fontSize: 64)),
          SizedBox(height: space.x6),
          Text(
            'You\'re Invited!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: space.x3),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
              children: [
                TextSpan(text: context.l10n.yourFriend),
                TextSpan(
                  text: inviterName,
                  style: context.coolText.manrope(
                    null,
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: context.l10n.invitedYouToJoin),
              ],
            ),
          ),
          SizedBox(height: space.x8),
          CoolCard(
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(space.x3),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.stars_rounded,
                    color: colors.accent,
                    size: 24,
                  ),
                ),
                SizedBox(width: space.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonus Points Waiting',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                      Text(
                        'Complete your first activity to earn 50 reward points.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: space.x10),
          CoolButton(
            label: context.l10n.getStarted,
            onTap: () {
              Navigator.pop(context);
              onAccept();
            },
          ),
        ],
      ),
    );
  }
}
