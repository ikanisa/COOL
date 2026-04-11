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
    final canJoin = onJoin != null;

    return CoolCard(
      onTap: onOpen,
      cardPadding: CoolCardPadding.none,
      padding: const EdgeInsets.all(CoolSpace.x4),
      child: CoolListTile(
        leading: CoolIconBox(
          icon: Icons.groups_2_outlined,
          accent: colors.accent,
        ),
        title: group.name,
        subtitle: context.l10n.memberCount(group.memberCount),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${formatWholeMoneyAmount(group.amount)} RWF',
              style: context.coolText.display(
                Theme.of(context).textTheme.titleMedium,
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: CoolSpace.x3),
            if (canJoin)
              SizedBox(
                width: 84,
                child: CoolButton(
                  label: context.l10n.groupsJoinUpper,
                  onTap: isBusy ? null : onJoin,
                  isLoading: isBusy,
                  fullWidth: false,
                  size: CoolButtonSize.sm,
                  variant: CoolButtonVariant.secondary,
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: colors.tertiaryText,
                size: 20,
              ),
          ],
        ),
        onTap: onOpen,
        showChevron: false,
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.03, end: 0.0);
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
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.titleLarge,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: CoolSpace.x3),
          SizedBox(
            width: 120,
            child: CoolButton(
              label: actionLabel,
              onTap: isLoading ? null : onAction,
              isLoading: isLoading,
              fullWidth: false,
            ),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: CoolEmptyView(
          compact: true,
          title: title,
          subtitle: message,
          icon: Icons.groups_rounded,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _DataPulseBadge extends StatelessWidget {
  const _DataPulseBadge();

  @override
  Widget build(BuildContext context) {
    return const StatusBadge.online();
  }
}
