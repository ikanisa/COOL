import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Optional app access setup screen.
///
/// Permissions stay contextual in COOL. This screen gives users a single
/// place to review and enable access ahead of time, but every permission
/// can still be granted later from the feature that needs it.
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
        ..addEntries(snapshots.map((s) => MapEntry(s.permission, s)));
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

  int get _grantedCount => _snapshots.values.where((s) => s.isReady).length;

  Future<void> _continue() async {
    setState(() => _isContinuing = true);
    await _service.markPermissionOnboardingComplete();
    if (!mounted) return;
    context.go(widget.redirectPath ?? AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(height: space.x12),

              // ── Header ──────────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: space.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      child: CoolCard(
                        padding: EdgeInsets.all(space.x3),
                        borderRadius: radii.lg,
                        backgroundColor: colors.chipSelectedBackground,
                        borderColor: colors.accent.withValues(alpha: 0.18),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: colors.accent,
                          size: 28,
                        ),
                      ),
                    ),
                    SizedBox(height: space.x5),
                    Text(
                      'App Access',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: space.x2),
                    Text(
                      'Turn on access only when you need it. You can skip now '
                      'and manage permissions later in Settings.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: space.x2),
                    if (!_isLoading)
                      Text(
                        '$_grantedCount/${_permissions.length} ready',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: space.x5),

              // ── Permission list ─────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CupertinoActivityIndicator())
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: space.x6),
                        itemCount: _permissions.length,
                        separatorBuilder: (_, _) => SizedBox(height: space.x2),
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
                padding: EdgeInsets.fromLTRB(
                  space.x6,
                  space.x3,
                  space.x6,
                  space.x6,
                ),
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final isReady = snapshot.isReady;
    final isUnavailable = snapshot.kind == AppAccessStateKind.notAvailable;

    return CoolCard(
      padding: EdgeInsets.all(space.x3),
      backgroundColor: colors.cardSurface,
      borderRadius: radii.lg,
      borderColor: isReady
          ? colors.accent.withValues(alpha: 0.3)
          : colors.border,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isReady
                  ? colors.accent.withValues(alpha: 0.08)
                  : colors.cardSurfaceStrong,
              borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
            ),
            alignment: Alignment.center,
            child: Icon(
              metadata.icon,
              color: isReady ? colors.accent : colors.secondaryText,
              size: 22,
            ),
          ),
          SizedBox(width: space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                SizedBox(height: space.x1),
                Text(
                  metadata.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: space.x2),
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
                color: colors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
              ),
              child: Icon(Icons.check_rounded, color: colors.accent, size: 18),
            )
          else if (isUnavailable)
            Text(
              'N/A',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.tertiaryText,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(72, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor: colors.accent,
        foregroundColor: colors.accentForeground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
        ),
      ),
      child: Text(
        'Allow',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
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
          'Optional. Import approved M-Money confirmations and auto-verify payments.',
    ),
    AppAccessPermission.location => const _OnboardingPermissionMeta(
      icon: Icons.location_on_outlined,
      title: 'Location',
      subtitle: 'Find rides, nearby partners, and trip tracking.',
    ),
    AppAccessPermission.contacts => const _OnboardingPermissionMeta(
      icon: Icons.contacts_outlined,
      title: 'Contacts',
      subtitle: 'Send money, invite friends, and pick contacts for groups.',
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
