import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/config/env_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/biopay_enrollment_draft.dart';
import '../providers/biopay_providers.dart';
import '../services/biopay_auth_gate_service.dart';

class BiopayRegisterScreen extends ConsumerStatefulWidget {
  const BiopayRegisterScreen({super.key});

  @override
  ConsumerState<BiopayRegisterScreen> createState() =>
      _BiopayRegisterScreenState();
}

class _BiopayRegisterScreenState extends ConsumerState<BiopayRegisterScreen> {
  late final TextEditingController _displayNameController;
  bool _consentAccepted = false;
  bool _isRevoking = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _displayNameController = TextEditingController(text: user?.fullName ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _revokeProfile() async {
    if (_isRevoking) {
      return;
    }
    setState(() => _isRevoking = true);
    try {
      final authResult = await ref
          .read(biopayAuthGateServiceProvider)
          .authorize(BiopayAuthAction.revocation);
      if (!mounted) {
        return;
      }
      if (!authResult.isAuthorized) {
        CoolToast.error(context, authResult.message);
        return;
      }

      await ref
          .read(biopayRepositoryProvider)
          .revoke(
            reason: 'User requested revocation from BioPay register screen',
          );
      ref.invalidate(biopayProfileProvider);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'BioPay enrollment revoked');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, error.toString());
    } finally {
      if (mounted) {
        setState(() => _isRevoking = false);
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.tryParse(EnvConfig.privacyPolicyUrl);
    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) {
      return;
    }

    CoolToast.error(context, context.l10n.openLinkError);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final user = ref.watch(authProvider).user;
    final activeProfile = ref.watch(biopayProfileProvider);
    final modelIssueAsync = ref.watch(biopayModelAssetIssueProvider);
    final route = _resolveRoute(user);
    final hasRoute = route != null;
    final modelIssue = modelIssueAsync.valueOrNull;

    return CoolScreenScaffold(
      title: 'Register My Face',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoolCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BioPay uses your signed-in profile and your existing MoMo receive route. No phone OTP is required.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: space.x4),
                CoolTextField(
                  label: 'Display name',
                  hint: 'How payers should see you',
                  controller: _displayNameController,
                  prefixIcon: Icons.badge_rounded,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
          SizedBox(height: space.x5),
          if (route == null)
            CoolCard(
              borderColor: colors.warning.withValues(alpha: 0.42),
              useGradient: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wallet route required',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    'Set a MoMo number or merchant code on your profile before BioPay enrollment can begin.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: space.x4),
                  CoolButton(
                    label: 'Open Wallet Setup',
                    onTap: () => context.push(AppRoutes.profileWallet),
                  ),
                ],
              ),
            )
          else
            CoolCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Receive route',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    route.$1 == MomoRecipientType.code
                        ? 'Merchant code'
                        : 'MoMo number',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x1),
                  Text(
                    route.$2,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: space.x5),
          activeProfile.when(
            data: (profile) => profile == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      CoolCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active enrollment',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: space.x2),
                            Text(
                              '${profile.displayName} · ID ${profile.publicId}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: space.x1),
                            Text(
                              '${profile.routeLabel}: ${profile.maskedRecipientValue}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: space.x4),
                            CoolButton(
                              label: 'Revoke BioPay',
                              variant: CoolButtonVariant.secondary,
                              isLoading: _isRevoking,
                              onTap: _revokeProfile,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: space.x5),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          if (modelIssue != null) ...[
            CoolCard(
              borderColor: colors.warning.withValues(alpha: 0.42),
              useGradient: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model asset required',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    modelIssue,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: space.x5),
          ],
          CoolCard(
            useGradient: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Theme(
                  data: Theme.of(context).copyWith(
                    checkboxTheme: CheckboxThemeData(
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return colors.accent;
                        }
                        return colors.cardSurfaceStrong;
                      }),
                    ),
                  ),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consentAccepted,
                    onChanged: (value) {
                      setState(() => _consentAccepted = value ?? false);
                    },
                    title: Text(
                      'I consent to BioPay face embedding and payout route storage.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    subtitle: Text(
                      'Stores face template and payout route. Revoke anytime here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                SizedBox(height: space.x2),
                Text(
                  'See Privacy Policy. No camera frames are saved.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: space.x3),
                TextButton.icon(
                  onPressed: _openPrivacyPolicy,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open Privacy Policy'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: space.x5),
          CoolButton(
            label: 'Continue to Face Capture',
            icon: Icons.camera_alt_rounded,
            onTap: !hasRoute || !_consentAccepted || modelIssue != null
                ? null
                : () async {
                    final draft = BiopayEnrollmentDraft(
                      displayName: _displayNameController.text.trim(),
                      routeType: route.$1,
                      recipientValue: route.$2,
                      countryCode: AppMarket.countryCode,
                      consentVersion: 'biopay-v1',
                    );
                    await context.push(
                      AppRoutes.biopayScanLocation(mode: 'enroll'),
                      extra: draft,
                    );
                    ref.invalidate(biopayProfileProvider);
                  },
          ),
        ],
      ),
    );
  }

  (MomoRecipientType, String)? _resolveRoute(UserProfile? user) {
    if (user == null) {
      return null;
    }
    final routeType = user.effectiveMomoRouteType;
    final value = user.momoRecipientValue;
    if (routeType == null || value.trim().isEmpty) {
      return null;
    }
    return (routeType, value.trim());
  }
}
