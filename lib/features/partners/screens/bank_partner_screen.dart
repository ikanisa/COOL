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
import '../widgets/bank_partner_widgets.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/partner_shared_widgets.dart';

class BankPartnerScreen extends ConsumerWidget {
  const BankPartnerScreen({required this.bankId, super.key});

  final String bankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
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
            color: colors.primaryText,
          ),
          actions: buildPartnerAppBarActions(
            context,
            homeColor: colors.primaryText,
          ),
          title: partnerAsync.when(
            data: (partner) => Text(
              partner?.name ?? context.l10n.partnerLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(
              context.l10n.partnerLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: partnerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(CoolSpace.x5),
            child: CoolSkeletonList(),
          ),
          error: (error, _) => PartnerErrorBody(
            message: error.toString(),
            onRetry: () => ref.invalidate(partnerBySlugProvider(bankId)),
          ),
          data: (partner) {
            if (partner == null) {
              return PartnerErrorBody(message: context.l10n.partnerNotFound);
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final servicesAsync = ref.watch(partnerServicesProvider(partner.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        CoolSpace.x6,
        CoolSpace.x2,
        CoolSpace.x6,
        CoolSpace.x7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BankHero(partner: partner),
          const SizedBox(height: CoolSpace.x4),
          servicesAsync.when(
            data: (services) =>
                BankServiceGrid(partner: partner, services: services),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: CoolSpace.x6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Center(
              child: Text(
                context.l10n.couldNotLoadServices,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
