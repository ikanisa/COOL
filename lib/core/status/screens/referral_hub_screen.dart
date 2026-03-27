import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../providers/referral_providers.dart';
import '../../models/referral_attribution.dart';
import '../../../core/l10n/l10n.dart';

class ReferralHubScreen extends ConsumerStatefulWidget {
  const ReferralHubScreen({super.key});

  @override
  ConsumerState<ReferralHubScreen> createState() => _ReferralHubScreenState();
}

class _ReferralHubScreenState extends ConsumerState<ReferralHubScreen> {
  ReferralInviteLink? _inviteLink;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInviteLink();
  }

  Future<void> _loadInviteLink() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(referralRepositoryProvider);
      final link = await repo.createInviteLink(
        inviteCode: 'COOL-APP-SHARE',
        baseUri: Uri.parse(
          'https://play.google.com/store/apps/details?id=app.cool.mobile',
        ),
        campaignId: 'REFER-AND-EARN-2026',
      );
      if (mounted) {
        setState(() {
          _inviteLink = link;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _copyLink() {
    if (_inviteLink == null) return;
    Clipboard.setData(ClipboardData(text: _inviteLink!.uri.toString()));
    CoolToast.info(context, 'Invite link copied to clipboard');
  }

  void _shareNative() {
    if (_inviteLink == null) return;
    final text =
        'Download Cool on Google Play and earn tokens! ${_inviteLink!.uri}';
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _openQr() {
    if (_inviteLink == null) return;
    QrShareSheet.show(
      context,
      groupName: 'Cool SuperApp',
      inviteUrl: _inviteLink!.uri.toString(),
      sheetTitle: 'Invite Friends',
      sheetSubtitle: context.l10n.scanThisQrCode,
      shareText: 'Download Cool on Google Play! ${_inviteLink!.uri}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  onPressed: () => context.pop(),
                  tooltip: context.l10n.back,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.primaryText,
                  ),
                ),
                title: Text(
                  'Refer & Earn',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  space.x4,
                  space.x2,
                  space.x4,
                  space.x8,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Hero Banner ──
                    Container(
                      padding: EdgeInsets.all(space.x6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.accent,
                            colors.accent.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(radii.lg),
                      ),
                      child: Column(
                        children: [
                          const Text('🎁', style: TextStyle(fontSize: 48)),
                          SizedBox(height: space.x3),
                          Text(
                            'Invite Friends, Earn Tokens',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: space.x2),
                          Text(
                            'Earn Cool Tokens for every friend who joins and completes their first activity.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: space.x8),

                    // ── Your Link ──
                    Text(
                      'Your Invite Link',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    SizedBox(height: space.x3),
                    CoolCard(
                      child: Column(
                        children: [
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: CoolSkeletonList(itemCount: 1),
                            )
                          else if (_inviteLink != null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: space.x4,
                                vertical: space.x3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.cardSurface,
                                borderRadius: BorderRadius.circular(radii.sm),
                                border: Border.all(color: colors.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _inviteLink!.uri.toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.secondaryText,
                                            fontFamily: 'monospace',
                                          ),
                                    ),
                                  ),
                                  SizedBox(width: space.x2),
                                  GestureDetector(
                                    onTap: _copyLink,
                                    child: Icon(
                                      Icons.copy_rounded,
                                      size: 20,
                                      color: colors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            CoolErrorView(
                              message: 'Could not generate link. Please check your connection.',
                              onRetry: _loadInviteLink,
                            ),
                          SizedBox(height: space.x5),
                          Row(
                            children: [
                              Expanded(
                                child: CoolButton(
                                  label: context.l10n.shareLink,
                                  icon: Icons.share_rounded,
                                  onTap: _shareNative,
                                ),
                              ),
                              SizedBox(width: space.x3),
                              Expanded(
                                child: CoolButton(
                                  label: context.l10n.qrCode,
                                  icon: Icons.qr_code_rounded,
                                  variant: CoolButtonVariant.secondary,
                                  onTap: _openQr,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: space.x8),

                    // ── How it works ──
                    Text(
                      'How it works',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    SizedBox(height: space.x4),
                    _StepRow(
                      number: '1',
                      title: context.l10n.sendInvite,
                      message: 'Share your link or QR code with friends.',
                      icon: Icons.send_rounded,
                    ),
                    SizedBox(height: space.x5),
                    _StepRow(
                      number: '2',
                      title: context.l10n.friendJoins,
                      message: 'They sign up using your unique link.',
                      icon: Icons.person_add_rounded,
                    ),
                    SizedBox(height: space.x5),
                    _StepRow(
                      number: '3',
                      title: context.l10n.earnTokens,
                      message: 'Earn tokens when they complete an activity.',
                      icon: Icons.stars_rounded,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.message,
    required this.icon,
  });

  final String number;
  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.accent,
            ),
          ),
        ),
        SizedBox(width: space.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
        ),
        Icon(icon, color: colors.tertiaryText, size: 24),
      ],
    );
  }
}
