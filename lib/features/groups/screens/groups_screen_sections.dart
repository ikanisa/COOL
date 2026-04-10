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
    final isPublic = group.visibility == 'public';
    final inviteable = onInvite != null;
    final canJoin = onJoin != null;
    final canContribute = onContribute != null;
    final hasRoute = groupHasContributionRoute(group);

    return Container(
      padding: EdgeInsets.all(space.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.standard(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: textTheme.display(
                        null,
                        color: colors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: space.x1),
                    Text(
                      '${group.memberCount} members • ${group.country} • ${group.type == 'community' ? 'Community' : 'Saving'}',
                      style: textTheme.mobiLabel(color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPublic
                      ? colors.info.withValues(alpha: 0.15)
                      : colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
                child: Text(
                  isPublic ? 'PUBLIC' : 'PRIVATE',
                  style: textTheme.mobiLabel(
                    color: isPublic ? colors.info : colors.warning,
                  ),
                ),
              ),
            ],
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x3),
            Text(
              group.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.mobiLabel(color: colors.secondaryText),
            ),
          ],
          SizedBox(height: space.x3),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x3,
              vertical: space.x2,
            ),
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE',
                      style: textTheme.mobiLabel(color: colors.tertiaryText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.amount} RWF',
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
                        style: textTheme.mobiLabel(color: colors.tertiaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.monthlyContribution} RWF',
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
                        style: textTheme.mobiLabel(color: colors.tertiaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.targetAmount} RWF',
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
          SizedBox(height: space.x3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy && canJoin ? null : onOpen,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primaryText,
                    backgroundColor: colors.buttonSecondaryBackground,
                    padding: EdgeInsets.symmetric(vertical: space.x3),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                    ),
                  ),
                  child: Text(inviteable ? 'OPEN / INVITE' : 'OPEN'),
                ),
              ),
              SizedBox(width: space.x2),
              Expanded(
                child: TextButton.icon(
                  onPressed: isBusy
                      ? null
                      : canJoin
                      ? onJoin
                      : inviteable
                      ? onInvite
                      : canContribute
                      ? onContribute
                      : onOpen,
                  icon: Icon(
                    canJoin
                        ? Icons.person_add_alt_1_rounded
                        : inviteable
                        ? Icons.ios_share_rounded
                        : hasRoute
                        ? Icons.payments_rounded
                        : Icons.arrow_forward_rounded,
                    color: colors.accentForeground,
                  ),
                  label: Text(
                    canJoin
                        ? 'JOIN'
                        : inviteable
                        ? 'INVITE'
                        : hasRoute && canContribute
                        ? 'CONTRIBUTE'
                        : 'DETAILS',
                    style: textTheme
                        .mobiLabel(color: colors.accentForeground)
                        .copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: EdgeInsets.symmetric(vertical: space.x3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0.0);
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

    return Container(
      padding: EdgeInsets.all(space.x4),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        boxShadow: CoolShadows.clay(accentColor: colors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: text.display(
                    null,
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
          Text(subtitle, style: text.mobiLabel(color: colors.secondaryText)),
          SizedBox(height: space.x3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isLoading ? null : onAction,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
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
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: const Center(child: CircularProgressIndicator()),
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
      child: Padding(
        padding: EdgeInsets.all(space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 48, color: colors.secondaryText),
            SizedBox(height: space.x3),
            Text(
              title,
              style: text.display(
                null,
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.mobiLabel(color: colors.secondaryText),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: space.x4),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataPulseBadge extends StatefulWidget {
  const _DataPulseBadge();

  @override
  State<_DataPulseBadge> createState() => _DataPulseBadgeState();
}

class _DataPulseBadgeState extends State<_DataPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final opacity = 0.4 + (_ctrl.value * 0.6);
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.success.withValues(alpha: opacity),
                  boxShadow: [
                    BoxShadow(
                      color: colors.success.withValues(alpha: opacity * 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text('LIVE', style: textTheme.mobiLabel(color: colors.success)),
        ],
      ),
    );
  }
}
