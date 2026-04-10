import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/biopay_profile.dart';
import '../providers/biopay_providers.dart';
import '../widgets/biopay_surface.dart';

class BiopayProfileScreen extends ConsumerStatefulWidget {
  const BiopayProfileScreen({super.key});

  @override
  ConsumerState<BiopayProfileScreen> createState() =>
      _BiopayProfileScreenState();
}

class _BiopayProfileScreenState extends ConsumerState<BiopayProfileScreen> {
  MomoRecipientType? _selectedType;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final profileAsync = ref.watch(biopayProfileProvider);
    final country = _resolveCountry(user, profileAsync.valueOrNull);
    final availableTypes = _availableTypes(
      user,
      profileAsync.valueOrNull,
      country,
    );
    final selectedType =
        _selectedType ??
        (profileAsync.valueOrNull?.routeType ??
            (availableTypes.isEmpty
                ? MomoRecipientType.phoneNumber
                : availableTypes.first));

    return profileAsync.when(
      data: (profile) => BiopayLightScaffold(
        topPadding: CoolSpace.x2,
        child: Column(
          children: [
            BiopayTopBar(
              title: 'Profile',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go(AppRoutes.biopayHome);
              },
            ),
            const SizedBox(height: CoolSpace.x5),
            _ProfileIdentityHeader(profile: profile),
            const SizedBox(height: CoolSpace.x6),
            if (availableTypes.length > 1) ...[
              BiopaySegmentedControl(
                labels: availableTypes
                    .map(
                      (type) => type == MomoRecipientType.phoneNumber
                          ? 'Number'
                          : 'Code',
                    )
                    .toList(growable: false),
                selectedIndex: availableTypes.indexOf(selectedType),
                onSelected: (index) {
                  setState(() => _selectedType = availableTypes[index]);
                },
              ),
              const SizedBox(height: CoolSpace.x4),
            ],
            BiopaySectionCard(
              height: 126,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BiopayFieldLabel(
                    label: selectedType == MomoRecipientType.code
                        ? 'Merchant Code'
                        : 'MoMo Number',
                  ),
                  const Spacer(),
                  Text(
                    _displayRecipient(
                      selectedType: selectedType,
                      user: user,
                      profile: profile,
                      country: country,
                    ),
                    style: context.coolText.headline(
                      Theme.of(context).textTheme.headlineMedium,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            _FaceIdCard(
              isReady: profile?.active ?? false,
              onTap: () => context.push(AppRoutes.biopayRegister),
            ),
            if (profile == null) ...[
              const SizedBox(height: CoolSpace.x5),
              Text(
                'Complete Face ID enrollment to pay with BioPay.',
                textAlign: TextAlign.center,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.bodyMedium,
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      loading: () => const _BiopayProfileLoadingScreen(),
      error: (error, stackTrace) => BiopayLightScaffold(
        child: Column(
          children: [
            const BiopayTopBar(title: 'Profile'),
            const SizedBox(height: CoolSpace.x8),
            Builder(
              builder: (context) {
                final colors = context.coolSemanticColors;
                return Column(
                  children: [
                    Text(
                      'Profile unavailable',
                      style: context.coolText.headline(
                        Theme.of(context).textTheme.headlineSmall,
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    Text(
                      'BioPay could not load your linked details right now.',
                      textAlign: TextAlign.center,
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.bodyMedium,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: CoolSpace.x6),
            BiopayPrimaryButton(
              label: 'Try Again',
              onTap: () => ref.invalidate(biopayProfileProvider),
            ),
          ],
        ),
      ),
    );
  }

  CoolCountry _resolveCountry(UserProfile? user, BiopayProfile? profile) {
    final countryCode =
        profile?.countryCode.trim() ??
        user?.country.trim() ??
        AppMarket.country.isoCode;
    return CoolCountryCatalog.byIsoCode(countryCode) ?? AppMarket.country;
  }

  List<MomoRecipientType> _availableTypes(
    UserProfile? user,
    BiopayProfile? profile,
    CoolCountry country,
  ) {
    final types = <MomoRecipientType>{};
    if ((user?.momoNumber.trim().isNotEmpty ?? false) ||
        profile?.routeType == MomoRecipientType.phoneNumber) {
      types.add(MomoRecipientType.phoneNumber);
    }
    if (country.supportsMomoCode &&
        ((user?.momoCode?.trim().isNotEmpty ?? false) ||
            profile?.routeType == MomoRecipientType.code)) {
      types.add(MomoRecipientType.code);
    }
    if (types.isEmpty) {
      types.add(MomoRecipientType.phoneNumber);
      if (country.supportsMomoCode) {
        types.add(MomoRecipientType.code);
      }
    }
    return types.toList(growable: false);
  }

  String _displayRecipient({
    required MomoRecipientType selectedType,
    required UserProfile? user,
    required BiopayProfile? profile,
    required CoolCountry country,
  }) {
    final raw = switch (selectedType) {
      MomoRecipientType.phoneNumber =>
        profile?.routeType == MomoRecipientType.phoneNumber
            ? profile?.recipientValue
            : (user?.momoNumber.trim().isNotEmpty ?? false)
            ? user!.momoNumber
            : null,
      MomoRecipientType.code =>
        profile?.routeType == MomoRecipientType.code
            ? profile?.recipientValue
            : user?.momoCode,
    };

    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return selectedType == MomoRecipientType.code
          ? 'Not Linked'
          : 'Not Added';
    }
    if (selectedType == MomoRecipientType.code) {
      return trimmed;
    }
    try {
      return country.normalizeNationalPhone(trimmed);
    } catch (_) {
      return trimmed;
    }
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({required this.profile});

  final BiopayProfile? profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Column(
      children: [
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.xl),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.person_outline_rounded,
            size: 66,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: CoolSpace.x5),
        Text(
          profile?.publicId.trim().isNotEmpty == true
              ? profile!.publicId
              : '--',
          style: context.coolText.headline(
            Theme.of(context).textTheme.displaySmall,
            color: colors.primaryText,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          'BioPay ID',
          style: context.coolText.mono(
            Theme.of(context).textTheme.labelLarge,
            color: colors.secondaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }
}

class _FaceIdCard extends StatelessWidget {
  const _FaceIdCard({required this.isReady, required this.onTap});

  final bool isReady;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        child: BiopaySectionCard(
          height: 120,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Face ID',
                      style: context.coolText.headline(
                        Theme.of(context).textTheme.headlineSmall,
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      isReady ? 'Ready' : 'Not set up',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.titleMedium,
                        color: isReady ? colors.success : colors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.center_focus_strong_rounded,
                size: 34,
                color: colors.primaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiopayProfileLoadingScreen extends StatelessWidget {
  const _BiopayProfileLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return BiopayLightScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 120),
          child: CircularProgressIndicator(color: colors.accent),
        ),
      ),
    );
  }
}
