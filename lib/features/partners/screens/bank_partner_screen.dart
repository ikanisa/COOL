import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/partner.dart';
import '../providers/partner_provider.dart';
import '../providers/partner_service_provider.dart';
import '../widgets/bank_partner_config.dart';
import '../widgets/bank_partner_widgets.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/partner_shared_widgets.dart';

class BankPartnerScreen extends ConsumerWidget {
  const BankPartnerScreen({required this.bankId, super.key});

  final String bankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerBySlugProvider(bankId));

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: buildPartnerBackButton(
            context,
            fallbackLocation: AppRoutes.partners,
            icon: Icons.arrow_back_ios_new_rounded,
            color: AppColors.text,
          ),
          actions: buildPartnerAppBarActions(
            context,
            homeColor: AppColors.text,
          ),
          title: partnerAsync.when(
            data: (partner) => Text(
              partner?.name ?? 'Partner',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(
              'Partner',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: partnerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(18),
            child: CoolSkeletonList(),
          ),
          error: (error, _) => PartnerErrorBody(
            message: error.toString(),
            onRetry: () => ref.invalidate(partnerBySlugProvider(bankId)),
          ),
          data: (partner) {
            if (partner == null) {
              return const PartnerErrorBody(message: 'Partner not found');
            }
            return _BankBody(partner: partner);
          },
        ),
      ),
    );
  }
}

class _BankBody extends ConsumerWidget {
  const _BankBody({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = bankConfigForSlug(partner.slug);
    final servicesAsync = ref.watch(
      currentCountryPartnerServicesProvider(partner.id),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BankHero(partner: partner, config: config),
          const SizedBox(height: 16),
          BankQuickActionGrid(partner: partner, config: config),
          const SizedBox(height: 16),
          BankSourceCard(config: config),
          const SizedBox(height: 18),
          servicesAsync.when(
            loading: () => const CoolSkeletonList(itemCount: 5),
            error: (e, _) => PartnerErrorCard(message: e.toString()),
            data: (services) {
              if (services.isEmpty) {
                return PartnerEmptyServicesCard(partnerName: partner.name);
              }

              final grouped = groupBankServices(services);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in grouped) ...[
                    PartnerSectionHeader(
                      category: group.key,
                      categoryMeta: bankCategoryMeta,
                    ),
                    const SizedBox(height: 12),
                    for (final service in group.value) ...[
                      PartnerServiceCard(
                        service: service,
                        partner: partner,
                        categoryMeta: bankCategoryMeta,
                        normalizeCategory: normalizeBankCategory,
                        onCtaTap: (ctx, {required action, topic}) =>
                            launchPartnerAction(
                              ctx,
                              partner,
                              action: action,
                              topic: topic,
                            ),
                        gradientWhen: (cat) =>
                            cat == 'digital' ? AppColors.blueGradient : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          BankSupportCard(partner: partner, config: config),
        ],
      ),
    );
  }
}
