import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/app_config_repository.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/models/engagement_feature_flags.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/admin_feature_rollout.dart';
import '../providers/admin_providers.dart';

part '../controllers/manage_app_config_view_model.dart';
part '../widgets/manage_app_config_sections.dart';
part '../widgets/manage_app_config_sheets.dart';

/// Admin screen for managing key-value app configuration.
class ManageAppConfigScreen extends ConsumerWidget {
  const ManageAppConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(adminAppConfigProvider);
    final partnerRoutesAsync = ref.watch(adminPartnerPaymentRoutesProvider);
    final partnersAsync = ref.watch(adminPartnersProvider);
    final countries = ref.watch(supportedCountriesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add config entry',
        hint: 'New config',
        child: FloatingActionButton(
          backgroundColor: AppColors.accent,
          onPressed: () => _showEditSheet(context, ref, null, countries),
          child: const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ),
      body: CoolAsyncView<List<Map<String, dynamic>>>(
        value: configAsync,
        onRetry: () => ref.invalidate(adminAppConfigProvider),
        emptyCheck: (_) => false,
        builder: (configs) {
          final viewModel = ManageAppConfigViewModel.fromEntries(configs);
          final partnerRoutes = partnerRoutesAsync.valueOrNull ?? const [];
          final partners = partnersAsync.valueOrNull ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            children: [
              Text(
                'App Config',
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 24),
              const AppConfigSectionHeader(
                title: 'Rollout Governance',
                subtitle:
                    'Manage kill switches rollout',
              ),
              const SizedBox(height: 12),
              ...viewModel.rollouts.map(
                (rollout) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RolloutCard(
                    rollout: rollout,
                    onEdit:
                        () =>
                            _showRolloutSheet(context, ref, rollout, countries),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const AppConfigSectionHeader(
                title: 'Mobility Subscription Recipient',
                subtitle:
                    'Set the MoMo code',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showMobilitySubscriptionSheet(
                    context,
                    ref,
                    null,
                    countries,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Recipient'),
                ),
              ),
              const SizedBox(height: 12),
              if (viewModel.mobilitySubscriptionConfigs.isEmpty)
                const EmptyConfigCard(
                  message:
                      'No mobility subscription MoMo',
                )
              else
                ...viewModel.mobilitySubscriptionConfigs.map(
                  (config) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MobilitySubscriptionConfigTile(
                      config: config,
                      countries: countries,
                      onEdit: () => _showMobilitySubscriptionSheet(
                        context,
                        ref,
                        config,
                        countries,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const AppConfigSectionHeader(
                title: 'Partner Payment Routes',
                subtitle:
                    'Manage Rwanda partner checkout',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: partners.isEmpty
                      ? null
                      : () => _showPartnerPaymentRouteSheet(
                            context,
                            ref,
                            null,
                            countries,
                            partners,
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Add route',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (partnerRoutesAsync.isLoading && partnerRoutes.isEmpty)
                const EmptyConfigCard(
                  message: 'Loading partner payment routes…',
                )
              else if (partnerRoutesAsync.hasError)
                EmptyConfigCard(
                  message:
                      'Load partner payment failed',
                )
              else if (partnerRoutes.isEmpty)
                const EmptyConfigCard(
                  message:
                      'No partner payment routes',
                )
              else
                ...partnerRoutes.map(
                  (route) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PartnerPaymentRouteConfigTile(
                      config: route,
                      countries: countries,
                      onEdit: () => _showPartnerPaymentRouteSheet(
                        context,
                        ref,
                        route,
                        countries,
                        partners,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const AppConfigSectionHeader(
                title: 'Additional Config',
                subtitle:
                    'Use the generic config',
              ),
              const SizedBox(height: 12),
              if (viewModel.genericConfigs.isEmpty)
                const EmptyConfigCard(
                  message:
                      'No non-rollout config entries',
                )
              else
                ...viewModel.genericConfigs.map(
                  (config) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ConfigTile(
                      config: config,
                      onEdit: () =>
                          _showEditSheet(context, ref, config, countries),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showPartnerPaymentRouteSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? route,
    List<CoolCountry> countries,
    List<Map<String, dynamic>> partners,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EditPartnerPaymentRouteSheet(
        route: route,
        ref: ref,
        countries: countries,
        partners: partners,
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? config,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          EditConfigSheet(config: config, ref: ref, countries: countries),
    );
  }

  void _showRolloutSheet(
    BuildContext context,
    WidgetRef ref,
    AdminFeatureRolloutConfig rollout,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          EditRolloutSheet(rollout: rollout, ref: ref, countries: countries),
    );
  }

  void _showMobilitySubscriptionSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? config,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EditMobilitySubscriptionCodeSheet(
        config: config,
        ref: ref,
        countries: countries,
      ),
    );
  }
}
