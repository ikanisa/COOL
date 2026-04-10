import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_glass_header_surface.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../core/utils/user_error.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final myGroupIds = ref.watch(myGroupIdsProvider);

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: groupAsync.when(
          data: (group) {
            if (group == null) {
              return _MissingGroupState(message: context.l10n.groupNotFound);
            }

            final isMember = myGroupIds.contains(group.id);
            final ledgerAsync = isMember
                ? ref.watch(
                    groupPaymentLedgerProvider(
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
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(AppRoutes.contributionCircles);
              },
              onJoin: isMember ? null : () => _joinPublicGroup(group),
              onContribute: isMember
                  ? () {
                      if (!groupHasContributionRoute(group)) {
                        CoolToast.info(
                          context,
                          'This group has no payment route configured yet.',
                        );
                        return;
                      }
                      launchGroupContribution(context, group: group).then((ok) {
                        if (!ok && context.mounted) {
                          CoolToast.error(
                            context,
                            'Could not launch MoMo USSD. Try dialing manually.',
                          );
                        }
                      });
                    }
                  : null,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _MissingGroupState(message: describeUserFacingError(error)),
        ),
      ),
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
    required this.onBack,
    required this.onJoin,
    required this.onContribute,
  });

  final Group group;
  final bool isMember;
  final bool isJoining;
  final String? inviteUrl;
  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final VoidCallback onBack;
  final VoidCallback? onJoin;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 84,
        flexibleSpace: const CoolGlassHeaderSurface(),
        leading: IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.l10n.groupDetailTitle),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(space.x4, space.x3, space.x4, space.x6),
        children: [
          Text(
            group.name,
            style: text.display(
              null,
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: space.x2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _MetaPill(label: group.visibility.toUpperCase()),
              _MetaPill(
                label: group.type == 'community' ? 'COMMUNITY' : 'SAVING',
              ),
              _MetaPill(
                label: '${group.memberCount} ${context.l10n.groupMembers}',
              ),
            ],
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x4),
            Text(
              group.description!,
              style: text.mobiLabel(color: colors.secondaryText),
            ),
          ],
          SizedBox(height: space.x4),
          Container(
            padding: EdgeInsets.all(space.x4),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              boxShadow: CoolShadows.ambientFloat(strength: 0.3),
            ),
            child: Column(
              children: [
                _StatRow(label: 'Balance', value: '${group.amount} RWF'),
                if (group.targetAmount > 0) ...[
                  SizedBox(height: space.x2),
                  _StatRow(label: 'Target', value: '${group.targetAmount} RWF'),
                ],
                if ((group.monthlyContribution ?? 0) > 0) ...[
                  SizedBox(height: space.x2),
                  _StatRow(
                    label: 'Contribution',
                    value: '${group.monthlyContribution} RWF',
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
              label: groupHasContributionRoute(group)
                  ? 'CONTRIBUTE WITH MOMO'
                  : 'CONTRIBUTION ROUTE PENDING',
              onTap: groupHasContributionRoute(group) ? onContribute : null,
              variant: groupHasContributionRoute(group)
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
            Container(
              padding: EdgeInsets.all(space.x4),
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: BorderRadius.circular(CoolRadii.md),
                boxShadow: CoolShadows.ambientFloat(strength: 0.3),
              ),
              child: Text(
                'This group is invite-only.',
                style: text.mobiLabel(color: colors.secondaryText),
              ),
            ),
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
          if (isMember) ...[
            SizedBox(height: space.x5),
            Text(
              context.l10n.ledgerTitle,
              style: text.display(
                null,
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x3),
            ledgerAsync.when(
              data: (page) {
                if (page.entries.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(space.x4),
                    decoration: BoxDecoration(
                      color: colors.cardSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      boxShadow: CoolShadows.ambientFloat(strength: 0.3),
                    ),
                    child: Text(
                      'No posted contributions yet.',
                      style: text.mobiLabel(color: colors.secondaryText),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final entry in page.entries)
                      Padding(
                        padding: EdgeInsets.only(bottom: space.x2),
                        child: _LedgerTile(entry: entry),
                      ),
                    SizedBox(height: space.x3),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.push(
                          AppRoutes.contributionCircleStatementsLocation(
                            group.id ?? '',
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.accent,
                          side: BorderSide.none,
                          backgroundColor: colors.buttonSecondaryBackground,
                          padding: EdgeInsets.symmetric(vertical: space.x3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CoolRadii.lg),
                          ),
                        ),
                        child: Text(
                          'VIEW ALL STATEMENTS',
                          style: text.mono(
                            null,
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Container(
                padding: EdgeInsets.all(space.x4),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  boxShadow: CoolShadows.ambientFloat(strength: 0.3),
                ),
                child: Text(
                  'Could not load the ledger.',
                  style: text.mobiLabel(color: colors.secondaryText),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        boxShadow: CoolShadows.ambientFloat(strength: 0.2),
      ),
      child: Text(
        label,
        style: context.coolText.mobiLabel(color: colors.secondaryText),
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
  const _LedgerTile({required this.entry});

  final PayeePaymentLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Row(
        children: [
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
              ],
            ),
          ),
          Text(
            '${entry.amount} ${entry.currency}',
            style: text.mono(null, color: colors.accentGold),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 84,
        flexibleSpace: const CoolGlassHeaderSurface(),
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(AppRoutes.contributionCircles);
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.l10n.groupDetailTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x7),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
    );
  }
}
