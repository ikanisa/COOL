import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../widgets/admin_workspace_gate.dart';

class AdminWorkspacesScreen extends ConsumerWidget {
  const AdminWorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final access = ref.watch(adminWorkspaceAccessProvider);
    final partnerWorkspacesAsync = ref.watch(adminPartnerWorkspacesProvider);
    final bankWorkspacesAsync = ref.watch(adminBankWorkspacesProvider);

    if (!access.hasAnyAdminAccess) {
      return const AdminAccessDeniedScaffold(
        title: 'Admin Workspaces',
        message: 'This account does not',
        fallbackLocation: AppRoutes.home,
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.go(AppRoutes.profile),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          Text(
            'Admin Workspaces',
            style: GoogleFonts.dmSans(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: palette.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 24),
          _IntroCard(
            hasPlatformAccess: access.hasPlatformAccess,
            hasPartnerAccess: access.hasPartnerAdminAccess,
            hasBankAccess: access.hasBankAdminAccess,
          ),
          if (access.hasPlatformAccess) ...[
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'Platform',
              subtitle:
                  'Global app operations content',
            ),
            const SizedBox(height: 12),
            _WorkspaceCard(
              title: 'Platform Admin',
              subtitle:
                  'Users partners services app',
              icon: Icons.admin_panel_settings_outlined,
              onTap: () => context.push(AppRoutes.adminPlatform),
            ),
          ],
          if (access.hasPartnerAdminAccess) ...[
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'Partner Workspaces',
              subtitle:
                  'Partner-scoped admin surfaces for',
            ),
            const SizedBox(height: 12),
            partnerWorkspacesAsync.when(
              data: (partners) => partners.isEmpty
                  ? const _EmptyWorkspaceCard(
                      message:
                          'No explicit partner workspace',
                    )
                  : Column(
                      children: partners
                          .map(
                            (partner) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _WorkspaceCard(
                                title: partner.name,
                                subtitle: partner.slug == 'rayon-sports'
                                    ? 'Open the current Rayon Sports admin workspace.'
                                    : 'Open the partner workspace foundation.',
                                icon: Icons.storefront_rounded,
                                onTap: () => context.push(
                                  partner.slug == 'rayon-sports'
                                      ? AppRoutes.adminRayon
                                      : AppRoutes.adminPartnerWorkspaceLocation(
                                          partner.id,
                                        ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
              loading: () => const _InlineLoadingCard(
                message: 'Loading partner workspaces...',
              ),
              error: (error, _) => _EmptyWorkspaceCard(
                message: 'Load partner workspaces failed',
              ),
            ),
          ],
          if (access.hasBankAdminAccess) ...[
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'Bank Custodian Workspaces',
              subtitle:
                  'Group savings oversight ledgers',
            ),
            const SizedBox(height: 12),
            bankWorkspacesAsync.when(
              data: (banks) => banks.isEmpty
                  ? const _EmptyWorkspaceCard(
                      message:
                          'No explicit bank workspace',
                    )
                  : Column(
                      children: banks
                          .map(
                            (bank) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _WorkspaceCard(
                                title: bank.name,
                                subtitle:
                                    'Open the bank custodian',
                                icon: Icons.account_balance_rounded,
                                onTap: () => context.push(
                                  AppRoutes.adminBankWorkspaceLocation(bank.id),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
              loading: () => const _InlineLoadingCard(
                message: 'Loading bank workspaces...',
              ),
              error: (error, _) => _EmptyWorkspaceCard(
                message: 'Load bank workspaces failed',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.hasPlatformAccess,
    required this.hasPartnerAccess,
    required this.hasBankAccess,
  });

  final bool hasPlatformAccess;
  final bool hasPartnerAccess;
  final bool hasBankAccess;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final roles = <String>[
      if (hasPlatformAccess) 'platform admin',
      if (hasPartnerAccess) 'partner admin',
      if (hasBankAccess) 'bank admin',
    ];
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open the right workspace',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Roles: ${roles.join(', ')}',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: palette.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      onTap: onTap,
      semanticsLabel: '$title workspace. $subtitle',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: palette.text, size: 22),
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.text2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: palette.text3,
          ),
        ],
      ),
    );
  }
}

class _InlineLoadingCard extends StatelessWidget {
  const _InlineLoadingCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkspaceCard extends StatelessWidget {
  const _EmptyWorkspaceCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Text(
        message,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: palette.text2,
          height: 1.4,
        ),
      ),
    );
  }
}
