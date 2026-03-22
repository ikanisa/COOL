import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// One-time post-auth permission onboarding screen.
///
/// Shown once after user's first successful OTP verification. Requests
/// SMS, Location, Contacts, Camera, Photos, and NFC permissions. The user
/// can allow or skip each one; skipped permissions are re-triggered
/// contextually when the user initiates a feature requiring that access.
class AppAccessOnboardingScreen extends ConsumerStatefulWidget {
  const AppAccessOnboardingScreen({this.redirectPath, super.key});

  final String? redirectPath;

  @override
  ConsumerState<AppAccessOnboardingScreen> createState() =>
      _AppAccessOnboardingScreenState();
}

class _AppAccessOnboardingScreenState
    extends ConsumerState<AppAccessOnboardingScreen> {
  static const _permissions = <AppAccessPermission>[
    AppAccessPermission.sms,
    AppAccessPermission.location,
    AppAccessPermission.contacts,
    AppAccessPermission.camera,
    AppAccessPermission.photos,
    AppAccessPermission.nfc,
  ];

  late final AppAccessService _service = ref.read(appAccessServiceProvider);
  final _snapshots = <AppAccessPermission, AppAccessSnapshot>{};
  final _busy = <AppAccessPermission>{};
  bool _isLoading = true;
  bool _isContinuing = false;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    final snapshots = await _service.getSnapshots(_permissions);
    if (!mounted) return;
    setState(() {
      _snapshots
        ..clear()
        ..addEntries(
          snapshots.map((s) => MapEntry(s.permission, s)),
        );
      _isLoading = false;
    });
  }

  Future<void> _requestPermission(AppAccessPermission permission) async {
    setState(() => _busy.add(permission));
    final snapshot = await _service.enableAndRequest(permission);
    if (!mounted) return;
    setState(() {
      _snapshots[permission] = snapshot;
      _busy.remove(permission);
    });
  }

  int get _grantedCount =>
      _snapshots.values.where((s) => s.isReady).length;

  Future<void> _continue() async {
    setState(() => _isContinuing = true);
    await _service.markPermissionOnboardingComplete();
    if (!mounted) return;
    context.go(widget.redirectPath ?? AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),

              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: palette.accentGlow,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.admin_panel_settings_outlined,
                        color: palette.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'App Access',
                      style: GoogleFonts.dmSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Cool needs a few permissions to deliver the best '
                      'experience. You can always change these later in Settings.',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: palette.text2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_isLoading)
                      Text(
                        '$_grantedCount/${_permissions.length} ready',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Permission list ─────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CupertinoActivityIndicator())
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _permissions.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final permission = _permissions[index];
                          final snapshot = _snapshots[permission];
                          if (snapshot == null) return const SizedBox.shrink();
                          return _PermissionCard(
                            metadata: _metadataFor(permission),
                            snapshot: snapshot,
                            isBusy: _busy.contains(permission),
                            onAllow: () => _requestPermission(permission),
                          );
                        },
                      ),
              ),

              // ── CTA ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: CoolButton(
                  label: 'Continue',
                  onTap: _continue,
                  isLoading: _isContinuing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Permission card ──────────────────────────────────────────────────

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.metadata,
    required this.snapshot,
    required this.isBusy,
    required this.onAllow,
  });

  final _OnboardingPermissionMeta metadata;
  final AppAccessSnapshot snapshot;
  final bool isBusy;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isReady = snapshot.isReady;
    final isUnavailable =
        snapshot.kind == AppAccessStateKind.notAvailable;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isReady ? palette.accent.withValues(alpha: 0.3) : palette.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isReady ? palette.accentGlow : palette.surface3,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              metadata.icon,
              color: isReady ? palette.accent : palette.text2,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metadata.subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: palette.text3,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isBusy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CupertinoActivityIndicator(radius: 10),
            )
          else if (isReady)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: palette.accentGlow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.check_rounded, color: palette.accent, size: 18),
            )
          else if (isUnavailable)
            Text(
              'N/A',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.text3,
              ),
            )
          else
            _AllowButton(onTap: onAllow),
        ],
      ),
    );
  }
}

class _AllowButton extends StatelessWidget {
  const _AllowButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Allow',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Permission metadata ──────────────────────────────────────────────

class _OnboardingPermissionMeta {
  const _OnboardingPermissionMeta({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

_OnboardingPermissionMeta _metadataFor(AppAccessPermission permission) {
  return switch (permission) {
    AppAccessPermission.sms => const _OnboardingPermissionMeta(
      icon: Icons.sms_outlined,
      title: 'SMS Access',
      subtitle:
          'Auto-verify M-Money payments and reconcile group contributions.',
    ),
    AppAccessPermission.location => const _OnboardingPermissionMeta(
      icon: Icons.location_on_outlined,
      title: 'Location',
      subtitle: 'Find rides, nearby partners, and trip tracking.',
    ),
    AppAccessPermission.contacts => const _OnboardingPermissionMeta(
      icon: Icons.contacts_outlined,
      title: 'Contacts',
      subtitle:
          'Send money, invite friends, and pick contacts for groups.',
    ),
    AppAccessPermission.camera => const _OnboardingPermissionMeta(
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      subtitle: 'Scan QR codes, KYC verification, and profile photos.',
    ),
    AppAccessPermission.photos => const _OnboardingPermissionMeta(
      icon: Icons.photo_library_outlined,
      title: 'Photos & Media',
      subtitle: 'Choose profile photos and upload documents from gallery.',
    ),
    AppAccessPermission.nfc => const _OnboardingPermissionMeta(
      icon: Icons.nfc_outlined,
      title: 'NFC',
      subtitle: 'Tap-to-pay and contactless transactions.',
    ),
  };
}
