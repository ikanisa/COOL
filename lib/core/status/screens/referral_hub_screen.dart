import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
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
      // Using a generic invite code for the hub
      final link = await repo.createInviteLink(
        inviteCode: 'COOL-APP-SHARE',
        baseUri: Uri.parse('https://cool.app/home'),
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
        'Join me on Cool! Get tokens and enjoy seamless services: ${_inviteLink!.uri}';
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
      shareText: 'Join me on Cool! ${_inviteLink!.uri}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return Scaffold(
      backgroundColor: palette.bg,
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
                  icon: Icon(Icons.arrow_back_rounded, color: palette.text),
                ),
                title: Text(
                  'Refer & Earn',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Hero Banner ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.accent,
                            palette.accent.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          const Text('🎁', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text(
                            'Invite Friends, Earn Tokens',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Earn 150 Cool Tokens for every friend who joins and completes their first activity.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Your Link ──
                    Text(
                      'Your Invite Link',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CoolCard(
                      child: Column(
                        children: [
                          if (_isLoading)
                            const LinearProgressIndicator()
                          else if (_inviteLink != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: palette.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _inviteLink!.uri.toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.dmMono(
                                        fontSize: 13,
                                        color: palette.text2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _copyLink,
                                    child: Icon(
                                      Icons.copy_rounded,
                                      size: 20,
                                      color: palette.accent,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const Text(
                              'Could not generate link. Please try again.',
                            ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: CoolButton(
                                  label: context.l10n.shareLink,
                                  icon: Icons.share_rounded,
                                  onTap: _shareNative,
                                ),
                              ),
                              const SizedBox(width: 12),
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
                    const SizedBox(height: 32),

                    // ── How it works ──
                    Text(
                      'How it works',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StepRow(
                      number: '1',
                      title: context.l10n.sendInvite,
                      message: 'Share your link or QR code with friends.',
                      icon: Icons.send_rounded,
                    ),
                    const SizedBox(height: 20),
                    _StepRow(
                      number: '2',
                      title: context.l10n.friendJoins,
                      message: 'They sign up using your unique link.',
                      icon: Icons.person_add_rounded,
                    ),
                    const SizedBox(height: 20),
                    _StepRow(
                      number: '3',
                      title: context.l10n.earnTokens,
                      message: 'Get 150 tokens when they complete an activity.',
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
    final palette = context.coolPalette;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: palette.surface,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              Text(
                message,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.text3,
                ),
              ),
            ],
          ),
        ),
        Icon(icon, color: palette.text3, size: 24),
      ],
    );
  }
}