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
    final theme = Theme.of(context);
    final textTheme = context.coolText;
    final space = context.coolSpace;
    final isPublic = group.visibility == 'public';
    final inviteable = onInvite != null;
    final canJoin = onJoin != null;
    final canContribute = onContribute != null;
    final hasRoute = groupHasContributionRoute(group);
    final primaryActionIcon = canJoin
        ? Icons.person_add_alt_1_rounded
        : inviteable
        ? Icons.ios_share_rounded
        : hasRoute
        ? Icons.payments_rounded
        : Icons.arrow_forward_rounded;
    final primaryActionLabel = canJoin
        ? 'JOIN'
        : inviteable
        ? 'INVITE'
        : hasRoute && canContribute
        ? 'CONTRIBUTE'
        : 'DETAILS';

    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: textTheme.display(
              theme.textTheme.titleLarge,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: space.x2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              if (group.type == 'community')
                const StatusBadge.community()
              else
                const StatusBadge.saving(),
              if (isPublic)
                const StatusBadge.public()
              else
                const StatusBadge.private(),
              StatusBadge(
                label: '${group.memberCount} MEMBERS',
                bgColor: colors.cardSurfaceStrong,
                textColor: colors.secondaryText,
              ),
            ],
          ),
          SizedBox(height: space.x2),
          Text(
            '${group.country} • ${group.type == 'community' ? 'Community' : 'Saving'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x3),
            Text(
              group.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
          SizedBox(height: space.x3),
          CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            borderRadius: CoolRadii.lg,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.tertiaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatAmount(group.amount)} RWF',
                      style: textTheme.mono(null, color: colors.accentGold),
                    ),
                  ],
                ),
                if ((group.monthlyContribution ?? 0) > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'CONTRIBUTION',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatAmount(group.monthlyContribution ?? 0)} RWF',
                        style: textTheme.mono(
                          null,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  )
                else if (group.targetAmount > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TARGET',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatAmount(group.targetAmount)} RWF',
                        style: textTheme.mono(
                          null,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(height: space.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: inviteable ? 'OPEN / INVITE' : 'OPEN',
                  onTap: isBusy && canJoin ? null : onOpen,
                  variant: CoolButtonVariant.secondary,
                ),
              ),
              SizedBox(width: space.x2),
              Expanded(
                child: CoolButton(
                  label: primaryActionLabel,
                  icon: primaryActionIcon,
                  onTap: isBusy
                      ? null
                      : canJoin
                      ? onJoin
                      : inviteable
                      ? onInvite
                      : canContribute
                      ? onContribute
                      : onOpen,
                  variant: CoolButtonVariant.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0.0);
  }

  String _formatAmount(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(s[i]);
    }
    return buf.toString();
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
                    fontWeight: FontWeight.w700,
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
                  fontWeight: FontWeight.w700,
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
      label: 'LIVE',
      bgColor: colors.appBackground,
      textColor: colors.success,
    );
  }
}
