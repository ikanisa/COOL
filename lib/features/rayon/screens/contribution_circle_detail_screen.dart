import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../../profile/services/momo_setup_guard.dart';
import '../models/rs_contribution_models.dart';
import '../providers/rs_contribution_provider.dart';
import '../rayon_payment.dart';
import '../providers/rayon_sports_provider.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/rayon_state_views.dart';

// ─────────────────────────────────────────────────────────
// Contribution Circle Detail Screen
// ─────────────────────────────────────────────────────────

class ContributionCircleDetailScreen extends ConsumerStatefulWidget {
  const ContributionCircleDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<ContributionCircleDetailScreen> createState() =>
      _ContributionCircleDetailScreenState();
}

class _ContributionCircleDetailScreenState
    extends ConsumerState<ContributionCircleDetailScreen> {
  final _msgController = TextEditingController();

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final groupAsync = ref.watch(
      contributionGroupDetailProvider(widget.groupId),
    );
    final messagesAsync = ref.watch(groupMessagesProvider(widget.groupId));
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;
    final fmt = NumberFormat.decimalPattern('en');

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.contributionCircles,
          color: Colors.white,
        ),
        title: Text(
          'CIRCLE DETAILS',
          style: text.rayonCondensed(
            const TextStyle(fontSize: 18),
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: RsColors.rsRed,
        secondaryColor: RsColors.rsGold,
        child: groupAsync.when(
          data: (group) {
            if (group == null) {
              return RayonErrorView(
                message: 'Circle not found',
                onRetry: () => ref.invalidate(
                  contributionGroupDetailProvider(widget.groupId),
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                // ── Progress Hero Card ──
                SliverPadding(
                  padding: const EdgeInsets.all(18),
                  sliver: SliverToBoxAdapter(
                    child: _ProgressHeroCard(group: group, fmt: fmt),
                  ),
                ),

                // ── Contribute CTA ──
                if (!group.isClosed)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverToBoxAdapter(
                      child: CoolButton(
                        label: 'CONTRIBUTE NOW',
                        onTap: () async {
                          final isReady = await ensureMomoSetupForAction(
                            context,
                            ref,
                            intent: MomoSetupIntent.contribute,
                            redirectLocation:
                                AppRoutes.contributionCircleDetailLocation(
                                  group.id,
                                ),
                          );
                          if (!context.mounted || !isReady) {
                            return;
                          }
                          _showContributeSheet(context, group, paymentRoute);
                        },
                        icon: Icons.volunteer_activism_rounded,
                      ),
                    ),
                  ),

                // ── Group Info Card ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: CoolCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ABOUT THIS CIRCLE',
                            style: text.rayon(
                              const TextStyle(fontSize: 11),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: colors.tertiaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (group.description != null &&
                              group.description!.isNotEmpty) ...[
                            Text(
                              group.description!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: colors.primaryText,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _InfoRow(
                            icon: group.groupType.icon,
                            label: 'TYPE',
                            value: group.groupType.label,
                            valueColor: group.groupType.color,
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: group.privacy.icon,
                            label: 'PRIVACY',
                            value: group.privacy.label,
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.people_alt_rounded,
                            label: 'MEMBERS',
                            value: '${group.memberCount}',
                          ),
                          if (group.deadline != null) ...[
                            const SizedBox(height: 8),
                            _InfoRow(
                              icon: Icons.schedule_rounded,
                              label: 'DEADLINE',
                              value: DateFormat(
                                'd MMMM yyyy',
                              ).format(group.deadline!).toUpperCase(),
                              valueColor: group.isExpired
                                  ? RsColors.rsRed
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // ── MESSAGES heading ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'CIRCLE CHAT',
                      style: text.rayonCondensed(
                        const TextStyle(fontSize: 22),
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // ── Messages list ──
                messagesAsync.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        sliver: SliverToBoxAdapter(
                          child: CoolCard(
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 32,
                                    color: colors.secondaryText,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No messages yet. Start the conversation!',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: colors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final msg = messages[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MessageBubble(message: msg),
                          );
                        }, childCount: messages.length),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'Could not load messages.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
          loading: RayonLoadingView.new,
          error: (e, _) => RayonErrorView(
            message: e.toString(),
            onRetry: () =>
                ref.invalidate(contributionGroupDetailProvider(widget.groupId)),
          ),
        ),
      ),
      // ── Message input bar ──
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          MediaQuery.of(context).viewPadding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: colors.appBackground.withValues(alpha: 0.95),
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgController,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.pill),
                    borderSide: BorderSide(color: colors.borderStrong),
                  ),
                  filled: true,
                  fillColor: colors.inputSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: RsColors.rsRed,
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContributeSheet(
    BuildContext context,
    RsContributionGroup group,
    PartnerPaymentRoute? paymentRoute,
  ) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.appBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CoolRadii.lg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            Text(
              'CONTRIBUTE TO ${group.name.toUpperCase()}',
              style: text.rayonCondensed(
                const TextStyle(fontSize: 22),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            CoolCard(
              borderColor: RsColors.rsRedBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paymentRoute == null
                        ? 'PAYMENT ROUTING PENDING'
                        : '${paymentRoute.partnerName.toUpperCase()} ROUTE',
                    style: text.rayon(
                      const TextStyle(fontSize: 11),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  Text(
                    paymentRoute == null
                        ? 'Admin must activate a MOMO recipient code.'
                        : group.paymentRecipientValue.isNotEmpty
                        ? group.paymentRecipientValue
                        : paymentRoute.providerLabel,
                    style: text.mono(
                      const TextStyle(fontSize: 16),
                      fontWeight: FontWeight.w900,
                      color: RsColors.rsGoldLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            CoolButton(
              label: paymentRoute == null
                  ? 'Payment route unavailable'
                  : 'Pay via ${paymentRoute.providerLabel}',
              isDisabled: paymentRoute == null,
              onTap: paymentRoute == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      CoolToast.info(
                        context,
                        'MOMO USSD dialer would launch here.',
                      );
                    },
              icon: Icons.phone_in_talk_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final content = _msgController.text.trim();
    if (content.isEmpty) return;

    final controller = ref.read(contributionGroupControllerProvider.notifier);
    final success = await controller.sendMessage(
      groupId: widget.groupId,
      content: content,
    );

    if (success) {
      _msgController.clear();
    } else {
      if (mounted) CoolToast.error(context, 'Failed to send message.');
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Progress Hero Card
// ═══════════════════════════════════════════════════════════

class _ProgressHeroCard extends StatelessWidget {
  const _ProgressHeroCard({required this.group, required this.fmt});

  final RsContributionGroup group;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.cardSurfaceStrong.withValues(alpha: 0.95),
            colors.cardSurface.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: group.groupType.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: group.groupType.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(CoolRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  group.groupType.icon,
                  size: 12,
                  color: group.groupType.color,
                ),
                const SizedBox(width: 6),
                Text(
                  group.groupType.label.toUpperCase(),
                  style: text.rayon(
                    const TextStyle(fontSize: 10),
                    fontWeight: FontWeight.w800,
                    color: group.groupType.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Group name
          Text(
            group.name.toUpperCase(),
            style: text.rayonCondensed(
              const TextStyle(fontSize: 28, height: 1.05),
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Progress
          if (group.targetAmount > 0) ...[
            RsProgressBar(
              progress: group.progress,
              fillColor: group.groupType.color,
              height: 10,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAISED',
                      style: GoogleFonts.dmMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmt.format(group.currentTotal)} RWF',
                      style: text.mono(
                        const TextStyle(fontSize: 20),
                        fontWeight: FontWeight.w900,
                        color: RsColors.rsGoldLight,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TARGET',
                      style: GoogleFonts.dmMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmt.format(group.targetAmount)} RWF',
                      style: text.mono(
                        const TextStyle(fontSize: 16),
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Chat Bubble
// ═══════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final RsGroupMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final alias =
        message.alias ?? message.senderId.substring(0, 6).toUpperCase();
    final time = DateFormat('HH:mm').format(message.createdAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                alias,
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsNavyLight,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                time,
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message.content,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: colors.primaryText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Info Row Helper
// ═══════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.secondaryText),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: context.coolText.rayon(
            const TextStyle(fontSize: 12),
            fontWeight: FontWeight.w800,
            color: valueColor ?? colors.primaryText,
          ),
        ),
      ],
    );
  }
}
