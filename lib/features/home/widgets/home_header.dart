import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../mobility/providers/mobility_location_provider.dart';
import '../../mobility/providers/mobility_provider.dart';
import '../../../core/l10n/l10n.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.ref,
    required this.palette,
    required this.l10n,
  });

  final WidgetRef ref;
  final CoolPalette palette;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isDriver = user?.isDriver ?? false;
    final mobilityState = ref.watch(mobilityProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final isOnline = mobilityState.isDriverOnline;
    final isUpdating = mobilityState.isUpdatingDriverStatus;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            l10n.navHome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displayLarge,
          ),
        ),
        const SizedBox(width: 8),

        // ── QR Scanner Icon ──
        Semantics(
          button: true,
          label: context.l10n.scanQrCode,
          hint: 'Opens MoMo QR scanner',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('${AppRoutes.scanner}?mode=momo'),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 22,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ),

        // ── Driver On/Off Toggle ──
        if (isDriver) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: isOnline ? 'Go offline' : 'Go online',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: isUpdating
                    ? null
                    : () {
                        final pos = locationState.position;
                        ref
                            .read(mobilityProvider.notifier)
                            .toggleDriverOnline(
                              pos?.latitude ?? 0,
                              pos?.longitude ?? 0,
                            );
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                        : palette.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isOnline
                          ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                          : palette.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUpdating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CupertinoActivityIndicator(radius: 7),
                        )
                      else
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline
                                ? const Color(0xFF22C55E)
                                : palette.text3,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOnline
                              ? const Color(0xFF22C55E)
                              : palette.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}