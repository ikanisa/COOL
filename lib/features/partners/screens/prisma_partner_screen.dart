import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/partner.dart';
import '../providers/partner_provider.dart';
import '../providers/partner_service_provider.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/partner_shared_widgets.dart';
import '../widgets/prisma_partner_config.dart';
import '../widgets/prisma_partner_widgets.dart';

class PrismaPartnerScreen extends ConsumerWidget {
  const PrismaPartnerScreen({super.key});

  static const _slug = 'prisma';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final partnerAsync = ref.watch(partnerBySlugProvider(_slug));

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
            color: colors.primaryText,
          ),
          actions: buildPartnerAppBarActions(
            context,
            homeColor: colors.primaryText,
          ),
          title: partnerAsync.when(
            data: (partner) => Text(
              partner?.name ?? context.l10n.prismaLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          centerTitle: true,
        ),
        body: partnerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(18),
            child: CoolSkeletonList(),
          ),
          error: (error, _) => PartnerErrorBody(message: error.toString()),
          data: (partner) {
            if (partner == null) {
              return PartnerErrorBody(message: context.l10n.partnerNotFound);
            }
            return _PrismaBody(partner: partner);
          },
        ),
      ),
    );
  }
}

class _PrismaBody extends ConsumerWidget {
  const _PrismaBody({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final servicesAsync = ref.watch(
      currentCountryPartnerServicesProvider(partner.id),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrismaHeroCard(partner: partner),
          const SizedBox(height: CoolSpace.x4),
          PrismaQuickActions(partner: partner),
          const SizedBox(height: CoolSpace.x4),
          PrismaStatsCard(partner: partner),
          const SizedBox(height: CoolSpace.x4),
          PrismaValuesCard(partner: partner),
          const SizedBox(height: 18),
          servicesAsync.when(
            loading: () => const CoolSkeletonList(itemCount: 6),
            error: (error, _) => PartnerErrorCard(message: error.toString()),
            data: (services) {
              if (services.isEmpty) {
                return PartnerEmptyServicesCard(partnerName: partner.name);
              }

              final grouped = groupPrismaServices(services);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in grouped) ...[
                    PartnerSectionHeader(
                      category: group.key,
                      categoryMeta: prismaCategoryMeta,
                      fallbackCategory: 'capability',
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    for (final service in group.value) ...[
                      PartnerServiceCard(
                        service: service,
                        partner: partner,
                        categoryMeta: prismaCategoryMeta,
                        normalizeCategory: normalizePrismaCategory,
                        onCtaTap: (ctx, {required action, topic}) =>
                            launchPrismaAction(
                              ctx,
                              partner,
                              action: action,
                              topic: topic,
                            ),
                        fallbackCategory: 'capability',
                        gradientWhen: (cat) => cat.endsWith('_agent')
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  colors.analyticsSurface,
                                  colors.cardSurfaceStrong,
                                ],
                              )
                            : null,
                      ),
                      const SizedBox(height: CoolSpace.x3),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: CoolSpace.x2),
          PrismaSupportCard(partner: partner),
        ],
      ),
    );
  }
}
