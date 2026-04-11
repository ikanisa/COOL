part of 'groups_screen.dart';

class _GroupLedgerCard extends StatelessWidget {
  const _GroupLedgerCard({
    required this.group,
    required this.isMember,
    required this.isBusy,
    required this.onOpen,
    this.onInvite,
    this.onJoin,
    this.onContribute,
  });

  final Group group;
  final bool isMember;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback? onInvite;
  final VoidCallback? onJoin;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;
    final space = context.coolSpace;
    final canJoin = onJoin != null;

    return GestureDetector(
      onTap: onOpen,
      child: CoolCard(
        borderRadius: CoolRadii.xl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name + member count ─────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: textTheme.display(
                      Theme.of(context).textTheme.titleLarge,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${group.memberCount}',
                  style: textTheme.mono(null, color: colors.tertiaryText),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.people_rounded,
                  size: 14,
                  color: colors.tertiaryText,
                ),
              ],
            ),

            SizedBox(height: space.x2),

            // ── Balance row ─────────────────────────────────
            Row(
              children: [
                Text(
                  '${formatWholeMoneyAmount(group.amount)} RWF',
                  style: textTheme.mono(null, color: colors.accentGold),
                ),
                const Spacer(),
                if (canJoin)
                  CoolButton(
                    label: context.l10n.groupsJoinUpper,
                    onTap: isBusy ? null : onJoin,
                    isLoading: isBusy,
                    variant: CoolButtonVariant.primary,
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: colors.tertiaryText),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0.0);
  }
}

class _InviteBanner extends StatelessWidget {
  const _InviteBanner({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: text.display(
                    Theme.of(context).textTheme.titleLarge,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
          ),
          SizedBox(height: space.x3),
          CoolButton(
            label: actionLabel,
            onTap: isLoading ? null : onAction,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

class _InviteBannerLoading extends StatelessWidget {
  const _InviteBannerLoading();

  @override
  Widget build(BuildContext context) {
    return const CoolCard(
      borderRadius: CoolRadii.xl,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: CoolCard(
          borderRadius: CoolRadii.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_rounded, size: 48, color: colors.secondaryText),
              SizedBox(height: space.x3),
              Text(
                title,
                style: text.display(
                  Theme.of(context).textTheme.titleLarge,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: space.x2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: space.x4),
                CoolButton(label: actionLabel!, onTap: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DataPulseBadge extends StatelessWidget {
  const _DataPulseBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return StatusBadge(
      label: context.l10n.groupsLiveUpper,
      bgColor: colors.appBackground,
      textColor: colors.success,
    );
  }
}
