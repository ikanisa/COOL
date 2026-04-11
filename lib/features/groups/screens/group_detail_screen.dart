import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../../../core/utils/user_error.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';
import '../widgets/transaction_allocation_sheet.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  bool _isJoining = false;

  Future<void> _joinPublicGroup(Group group) async {
    if (_isJoining) {
      return;
    }

    // Gate: require verified phone before joining a group.
    if (!await requireVerifiedUser(context, ref)) {
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      return;
    }

    setState(() => _isJoining = true);
    try {
      final result = await ref
          .read(groupRepositoryProvider)
          .joinPublicGroup(group: group, user: user);
      ref.read(groupsRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      CoolToast.success(
        context,
        result.isAlreadyMember
            ? context.l10n.alreadyMemberOf(group.name)
            : context.l10n.youJoinedGroup(group.name),
      );
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, describeUserFacingError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _contributeToGroup(Group group) async {
    if (!await requireVerifiedUser(context, ref)) {
      return;
    }

    if (!groupHasContributionRoute(group)) {
      CoolToast.info(
        context,
        'This group has no payment route configured yet.',
      );
      return;
    }

    final launched = await launchGroupContribution(context, group: group);
    if (!launched && mounted) {
      CoolToast.error(
        context,
        'Could not launch MoMo USSD. Try dialing manually.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final accessAsync = ref.watch(groupAccessProvider(widget.groupId));
    final myGroupIds = ref.watch(myGroupIdsProvider);

    return groupAsync.when(
      data: (group) {
        if (group == null) {
          return _MissingGroupState(message: context.l10n.groupNotFound);
        }

        final access = accessAsync.valueOrNull;
        final isMember = access?.isMember ?? myGroupIds.contains(group.id);
        final canManageSettings = access?.canManageSettings ?? false;
        final canViewTransactions = access?.canViewTransactions ?? false;
        final ledgerAsync = canViewTransactions
            ? ref.watch(
                groupTransactionFeedProvider(
                  GroupPaymentLedgerQuery(
                    groupId: group.id ?? '',
                    statementQuery: const MomoStatementQuery(limit: 10),
                  ),
                ),
              )
            : const AsyncData(MomoStatementPage<PayeePaymentLedgerEntry>());
        final inviteUrl = buildGroupInviteUrl(group);

        return _GroupDetailBody(
          group: group,
          isMember: isMember,
          isJoining: _isJoining,
          inviteUrl: inviteUrl,
          ledgerAsync: ledgerAsync,
          canManageSettings: canManageSettings,
          canViewTransactions: canViewTransactions,
          onBack: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(AppRoutes.contributionCircles);
          },
          onJoin: isMember ? null : () => _joinPublicGroup(group),
          onOpenSettings: canManageSettings
              ? () => context.push(
                  AppRoutes.contributionCircleSettingsLocation(group.id ?? ''),
                )
              : null,
          onContribute: isMember ? () => _contributeToGroup(group) : null,
        );
      },
      loading: () => const CoreDetailScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) =>
          _MissingGroupState(message: describeUserFacingError(error)),
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({
    required this.group,
    required this.isMember,
    required this.isJoining,
    required this.inviteUrl,
    required this.ledgerAsync,
    required this.canManageSettings,
    required this.canViewTransactions,
    required this.onBack,
    required this.onJoin,
    required this.onOpenSettings,
    required this.onContribute,
  });

  final Group group;
  final bool isMember;
  final bool isJoining;
  final String? inviteUrl;
  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final bool canManageSettings;
  final bool canViewTransactions;
  final VoidCallback onBack;
  final VoidCallback? onJoin;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final text = context.coolText;
    final space = context.coolSpace;
    final currency = CoolCountryCatalog.resolve(
      country: group.country,
    ).currencyCode;
    final routeReady = groupHasContributionRoute(group);

    return CoreDetailScaffold(
      onBack: onBack,
      title: Text(
        group.name,
        style: text.displayCondensed(
          theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _MetaBadge(label: group.visibility.toUpperCase()),
              _MetaBadge(
                label: group.type == 'community' ? 'COMMUNITY' : 'SAVING',
              ),
              _MetaBadge(
                label: '${group.memberCount} ${context.l10n.groupMembers}',
              ),
            ],
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x3),
            Text(
              group.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
        ],
      ),
      actions: canManageSettings
          ? <Widget>[
              IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
              const SizedBox(width: CoolSpace.x2),
            ]
          : null,
      child: ListView(
        padding: const EdgeInsets.only(bottom: CoolSpace.x7),
        children: [
          CoolCard(
            borderRadius: CoolRadii.xl,
            child: Column(
              children: [
                _StatRow(
                  label: 'Balance',
                  value: '${formatWholeMoneyAmount(group.amount)} $currency',
                ),
                if (group.targetAmount > 0) ...[
                  SizedBox(height: space.x2),
                  _StatRow(
                    label: 'Target',
                    value:
                        '${formatWholeMoneyAmount(group.targetAmount)} $currency',
                  ),
                ],
                if ((group.monthlyContribution ?? 0) > 0) ...[
                  SizedBox(height: space.x2),
                  _StatRow(
                    label: 'Contribution',
                    value:
                        '${formatWholeMoneyAmount(group.monthlyContribution ?? 0)} $currency',
                  ),
                ],
                SizedBox(height: space.x2),
                _StatRow(label: 'Country', value: group.country),
              ],
            ),
          ),
          SizedBox(height: space.x5),
          if (isMember)
            CoolButton(
              label: routeReady
                  ? 'CONTRIBUTE WITH MOMO'
                  : 'CONTRIBUTION ROUTE PENDING',
              onTap: routeReady ? onContribute : null,
              variant: routeReady
                  ? CoolButtonVariant.accent
                  : CoolButtonVariant.secondary,
            )
          else if (group.visibility == 'public')
            CoolButton(
              label: 'JOIN GROUP',
              onTap: isJoining ? null : onJoin,
              isLoading: isJoining,
            )
          else
            const _DetailNoticeCard(message: 'This group is invite-only.'),
          if (inviteUrl != null && isMember) ...[
            SizedBox(height: space.x5),
            ShareCard(
              title: context.l10n.inviteToGroup(group.name),
              subtitle: 'Share the invite link with your members.',
              shareUrl: inviteUrl!,
              shareText: context.l10n.joinGroupShareText(
                group.name,
                inviteUrl!,
              ),
              analyticsTargetType: 'group_invite',
            ),
          ],
          if (canViewTransactions) ...[
            SizedBox(height: space.x5),
            Text(
              context.l10n.ledgerTitle,
              style: text.display(
                theme.textTheme.titleLarge,
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: space.x3),
            ledgerAsync.when(
              data: (page) {
                if (page.entries.isEmpty) {
                  return Column(
                    children: [
                      const _DetailNoticeCard(
                        message: 'No posted contributions yet.',
                      ),
                      SizedBox(height: space.x3),
                      _StatementsButton(groupId: group.id ?? ''),
                    ],
                  );
                }

                return Column(
                  children: [
                    for (final entry in page.entries)
                      Padding(
                        padding: EdgeInsets.only(bottom: space.x2),
                        child: _LedgerTile(
                          entry: entry,
                          canManageAllocations: canManageSettings,
                          groupId: group.id ?? '',
                        ),
                      ),
                    SizedBox(height: space.x3),
                    _StatementsButton(groupId: group.id ?? ''),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Column(
                children: [
                  const _DetailNoticeCard(
                    message: 'Could not load the ledger.',
                  ),
                  SizedBox(height: space.x3),
                  _StatementsButton(groupId: group.id ?? ''),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatementsButton extends StatelessWidget {
  const _StatementsButton({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CoolButton(
        label: 'VIEW ALL STATEMENTS',
        onTap: () => context.push(
          AppRoutes.contributionCircleStatementsLocation(groupId),
        ),
        variant: CoolButtonVariant.secondary,
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return StatusBadge(
      label: label,
      bgColor: colors.cardSurfaceStrong,
      textColor: colors.secondaryText,
    );
  }
}

class _DetailNoticeCard extends StatelessWidget {
  const _DetailNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: text.mobiLabel(color: colors.tertiaryText),
        ),
        Text(value, style: text.mono(null, color: colors.primaryText)),
      ],
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.entry,
    this.canManageAllocations = false,
    this.groupId = '',
  });

  final PayeePaymentLedgerEntry entry;
  final bool canManageAllocations;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final isAllocated = entry.payerUserId.trim().isNotEmpty;
    final statusLabel = isAllocated ? 'confirmed' : 'pending_review';

    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.payments_rounded, color: colors.accent, size: 20),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: text.display(
                    null,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  '${entry.payerName} • ${entry.occurredAt.toLocal().toString().split('.').first}',
                  style: text.mobiLabel(color: colors.secondaryText),
                ),
                const SizedBox(height: 4),
                TransactionStatusChip(status: statusLabel),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                style: text.mono(null, color: colors.accentGold),
              ),
              if (canManageAllocations) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    onPressed: () => TransactionAllocationSheet.show(
                      context,
                      entry: entry,
                      groupId: groupId,
                    ),
                    icon: Icon(Icons.tune_rounded, color: colors.secondaryText),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingGroupState extends StatelessWidget {
  const _MissingGroupState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoreDetailScaffold(
      onBack: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        context.go(AppRoutes.contributionCircles);
      },
      title: Text(
        context.l10n.groupDetailTitle,
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Center(
        child: CoolCard(
          borderRadius: CoolRadii.xl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.operationalSurface,
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.group_off_rounded,
                    size: 36,
                    color: colors.tertiaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x5),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: context.l10n.goBack,
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go(AppRoutes.contributionCircles);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
