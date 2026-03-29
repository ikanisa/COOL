import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_market.dart';
import '../../../../core/config/country_catalog.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/utils/phone_validator.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_text_field.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/momo_route_type_selector.dart';
import '../../../../shared/widgets/rs_circle_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/momo_setup_guard.dart';
import '../models/rs_contribution_models.dart';
import '../providers/rs_contribution_provider.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/rayon_state_views.dart';

// ─────────────────────────────────────────────────────────
// Contribution Circles Hub — Two‑tab layout
// ─────────────────────────────────────────────────────────

class ContributionCirclesScreen extends ConsumerStatefulWidget {
  const ContributionCirclesScreen({super.key});

  @override
  ConsumerState<ContributionCirclesScreen> createState() =>
      _ContributionCirclesScreenState();
}

class _ContributionCirclesScreenState
    extends ConsumerState<ContributionCirclesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.appBackground.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.8)),
            ),
          ),
        ),
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.rayonHome,
          color: Colors.white,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CONTRIBUTION',
              style: text.rayonCondensed(
                const TextStyle(fontSize: 18),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              'CIRCLES',
              style: text.rayonCondensed(
                const TextStyle(fontSize: 16),
                fontWeight: FontWeight.w900,
                color: RsColors.rsNavyLight,
              ),
            ),
            Text(
              'GIKUNDIRO TOGETHER',
              style: GoogleFonts.dmMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: RsColors.rsRed,
          indicatorWeight: 3,
          labelStyle: text.rayon(
            const TextStyle(fontSize: 14),
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          unselectedLabelStyle: text.rayon(
            const TextStyle(fontSize: 14),
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
          tabs: const [
            Tab(text: 'MY CIRCLES'),
            Tab(text: 'PUBLIC'),
          ],
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: RsColors.rsRed,
        secondaryColor: RsColors.rsGold,
        child: TabBarView(
          controller: _tabController,
          children: [_MyCirclesTab(), _PublicCirclesTab()],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final isReady = await ensureMomoSetupForAction(
            context,
            ref,
            intent: MomoSetupIntent.createGroup,
            redirectLocation: AppRoutes.contributionCircles,
          );
          if (!context.mounted || !isReady) {
            return;
          }
          _showCreateCircleSheet(context);
        },
        backgroundColor: RsColors.rsRed,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'CREATE GROUP',
          style: text.rayon(
            const TextStyle(fontSize: 13),
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showCreateCircleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.coolSemanticColors.appBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CoolRadii.lg)),
      ),
      builder: (_) => _CreateCircleSheet(ref: ref),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Tab: My Circles
// ═══════════════════════════════════════════════════════════

class _MyCirclesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myGroups = ref.watch(myContributionGroupsProvider);

    return myGroups.when(
      data: (groups) {
        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.group_add_rounded,
                    size: 48,
                    color: context.coolSemanticColors.secondaryText,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'NO CIRCLES YET',
                    style: context.coolText.rayonCondensed(
                      const TextStyle(fontSize: 22),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a contribution circle to rally Gikundiro fans together.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.coolSemanticColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final group = groups[index];
            return RsCircleCard(
              group: group,
              onTap: () =>
                  context.push('${AppRoutes.contributionCircles}/${group.id}'),
            );
          },
        );
      },
      loading: RayonLoadingView.new,
      error: (e, _) => RayonErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(myContributionGroupsProvider),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Tab: Public Circles
// ═══════════════════════════════════════════════════════════

class _PublicCirclesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicGroups = ref.watch(publicContributionGroupsProvider);

    return publicGroups.when(
      data: (groups) {
        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.public_rounded,
                    size: 48,
                    color: context.coolSemanticColors.secondaryText,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'NO PUBLIC CIRCLES',
                    style: context.coolText.rayonCondensed(
                      const TextStyle(fontSize: 22),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Public contribution circles from the club will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.coolSemanticColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final group = groups[index];
            return RsCircleCard(
              group: group,
              onTap: () =>
                  context.push('${AppRoutes.contributionCircles}/${group.id}'),
            );
          },
        );
      },
      loading: RayonLoadingView.new,
      error: (e, _) => RayonErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(publicContributionGroupsProvider),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Create Circle Bottom Sheet
// ═══════════════════════════════════════════════════════════

class _CreateCircleSheet extends StatefulWidget {
  const _CreateCircleSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateCircleSheet> createState() => _CreateCircleSheetState();
}

class _CreateCircleSheetState extends State<_CreateCircleSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  late final TextEditingController _momoNumberCtrl;
  late final TextEditingController _momoCodeCtrl;
  ContributionGroupType _type = ContributionGroupType.community;
  GroupPrivacy _privacy = GroupPrivacy.public;
  late MomoRecipientType _selectedRouteType;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = widget.ref.read(authProvider).user;
    final country = AppMarket.country;
    final savedNumber = user?.momoNumber.trim() ?? '';
    final localNumber = savedNumber.isEmpty
        ? ''
        : () {
            try {
              return country.normalizeNationalPhone(savedNumber);
            } catch (_) {
              return savedNumber;
            }
          }();
    final savedCode = user?.momoCode?.trim() ?? '';
    _momoNumberCtrl = TextEditingController(text: localNumber);
    _momoCodeCtrl = TextEditingController(
      text: country.supportsMomoCode ? savedCode : '',
    );
    _selectedRouteType =
        user?.effectiveMomoRouteType ??
        (savedCode.isNotEmpty && localNumber.isEmpty
            ? MomoRecipientType.code
            : MomoRecipientType.phoneNumber);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    _momoNumberCtrl.dispose();
    _momoCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        16,
        22,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
              'CREATE GROUP',
              style: text.rayonCondensed(
                const TextStyle(fontSize: 24),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              'RALLY GIKUNDIRO FANS TOGETHER',
              style: GoogleFonts.dmMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),

            // Name field
            CoolTextField(
              hint: 'Circle Name',
              label: 'Circle Name',
              controller: _nameCtrl,
            ),
            const SizedBox(height: CoolSpace.x4),

            // Description field
            CoolTextField(
              hint: 'Brief description',
              label: 'Description (optional)',
              controller: _descCtrl,
              maxLines: 2,
            ),
            const SizedBox(height: CoolSpace.x4),

            // Target amount
            CoolTextField(
              hint: 'e.g. 500000',
              label: 'Target Amount (RWF)',
              controller: _targetCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: CoolSpace.x4),

            Text(
              'GROUP COLLECTION MOMO',
              style: text.rayon(
                const TextStyle(fontSize: 11),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: colors.tertiaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Defaults to your Settings wallet. Override it here without changing your saved profile MoMo.',
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.45,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            if (AppMarket.country.supportsMomoCode) ...[
              MomoRouteTypeSelector(
                value: _selectedRouteType,
                onChanged: (value) =>
                    setState(() => _selectedRouteType = value),
                phoneLabel: 'MoMo Number',
                codeLabel: 'MoMo Code',
              ),
              const SizedBox(height: CoolSpace.x4),
            ],
            CoolTextField(
              hint: AppMarket.country.phoneExampleHint(),
              label: 'Group MoMo Number',
              controller: _momoNumberCtrl,
              keyboardType: TextInputType.phone,
            ),
            if (AppMarket.country.supportsMomoCode) ...[
              const SizedBox(height: CoolSpace.x4),
              CoolTextField(
                hint: AppMarket.country.momoCodeExample ?? '12345',
                label: 'Group MoMo Code',
                controller: _momoCodeCtrl,
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: CoolSpace.x6),

            // Type selector
            Text(
              'CIRCLE TYPE',
              style: text.rayon(
                const TextStyle(fontSize: 11),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: colors.tertiaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ContributionGroupType.values.map((type) {
                final selected = type == _type;
                return GestureDetector(
                  onTap: () => setState(() => _type = type),
                  child: AnimatedContainer(
                    duration: CoolMotion.quick,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? type.color.withValues(alpha: 0.2)
                          : colors.inputSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                      border: Border.all(
                        color: selected ? type.color : colors.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type.icon,
                          size: 14,
                          color: selected ? type.color : colors.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type.label.toUpperCase(),
                          style: text.rayon(
                            const TextStyle(fontSize: 11),
                            fontWeight: FontWeight.w800,
                            color: selected ? type.color : colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: CoolSpace.x6),

            // Privacy selector
            Text(
              'PRIVACY',
              style: text.rayon(
                const TextStyle(fontSize: 11),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: colors.tertiaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Wrap(
              spacing: 8,
              children: GroupPrivacy.values.map((p) {
                final selected = p == _privacy;
                return GestureDetector(
                  onTap: () => setState(() => _privacy = p),
                  child: AnimatedContainer(
                    duration: CoolMotion.quick,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? RsColors.rsNavyLight.withValues(alpha: 0.2)
                          : colors.inputSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                      border: Border.all(
                        color: selected ? RsColors.rsNavyLight : colors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          p.icon,
                          size: 14,
                          color: selected
                              ? RsColors.rsNavyLight
                              : colors.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.label.toUpperCase(),
                          style: text.rayon(
                            const TextStyle(fontSize: 11),
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? RsColors.rsNavyLight
                                : colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: CoolSpace.x7),

            // Submit button
            CoolButton(
              label: _isSubmitting ? 'CREATING...' : 'CREATE GROUP',
              isDisabled: _isSubmitting,
              onTap: _isSubmitting ? null : _submit,
              icon: Icons.auto_awesome_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      CoolToast.info(context, 'Group name is required.');
      return;
    }

    final country = AppMarket.country;
    final momoNumber = _momoNumberCtrl.text.trim();
    final momoCode = country.supportsMomoCode ? _momoCodeCtrl.text.trim() : '';
    final routeType = country.supportsMomoCode
        ? _selectedRouteType
        : MomoRecipientType.phoneNumber;

    final numberError = momoNumber.isEmpty
        ? routeType == MomoRecipientType.phoneNumber
              ? 'Group MoMo number is required.'
              : null
        : PhoneValidator.validateMomoNumberForCountry(momoNumber, country);
    if (numberError != null) {
      CoolToast.info(context, numberError);
      return;
    }

    final codeError = momoCode.isEmpty
        ? routeType == MomoRecipientType.code
              ? 'Group MoMo code is required.'
              : null
        : PhoneValidator.validateMomoCode(momoCode, country: country);
    if (codeError != null) {
      CoolToast.info(context, codeError);
      return;
    }

    setState(() => _isSubmitting = true);

    final target =
        int.tryParse(_targetCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final controller = widget.ref.read(
      contributionGroupControllerProvider.notifier,
    );
    final result = await controller.createGroup(
      name: name,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      groupType: _type,
      privacy: _privacy,
      targetAmount: target,
      momoNumber: momoNumber.isEmpty ? null : momoNumber,
      momoCode: momoCode.isEmpty ? null : momoCode,
      momoRouteType: routeType,
    );

    if (!mounted) return;

    if (result != null) {
      CoolToast.success(context, 'Group "$name" created!');
      Navigator.of(context).pop();
    } else {
      CoolToast.error(context, 'Failed to create group.');
      setState(() => _isSubmitting = false);
    }
  }
}
