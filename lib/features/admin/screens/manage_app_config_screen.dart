
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'App Config',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null, countries),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CoolAsyncView<List<Map<String, dynamic>>>(
          value: configAsync,
          onRetry: () => ref.invalidate(adminAppConfigProvider),
          emptyCheck: (_) => false,
          builder: (configs) {
            final viewModel = ManageAppConfigViewModel.fromEntries(configs);
            final partnerRoutes = partnerRoutesAsync.valueOrNull ?? const [];
            final partners = partnersAsync.valueOrNull ?? const [];
            return ListView(
              children: [
                AppConfigSectionHeader(
                  title: 'Rollout Governance',
                  subtitle:
                      'Manage kill switches, rollout stage, market allow-lists, and operator-only access for the app shell.',
                ),
                const SizedBox(height: 12),
                ...viewModel.rollouts.map(
                  (rollout) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RolloutCard(
                      rollout: rollout,
                      onEdit: () =>
                          _showRolloutSheet(context, ref, rollout, countries),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppConfigSectionHeader(
                  title: 'Mobility Subscription Recipient',
                  subtitle:
                      'Set the MoMo code that receives mobility subscription payments. Add a global default or country override here instead of using build flags.',
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Add code',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (viewModel.mobilitySubscriptionConfigs.isEmpty)
                  const EmptyConfigCard(
                    message:
                        'No mobility subscription MoMo code is configured yet. Add one before drivers can pay subscriptions.',
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
                AppConfigSectionHeader(
                  title: 'Partner Payment Routes',
                  subtitle:
                      'Manage per-partner merchant codes, providers, reconciliation labels, and active checkout status without shipping a new app build.',
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
                        'Could not load partner payment routes. ${partnerRoutesAsync.error}',
                  )
                else if (partnerRoutes.isEmpty)
                  const EmptyConfigCard(
                    message:
                        'No partner payment routes are configured yet. Add an active merchant-code route before partner checkout goes live.',
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
                AppConfigSectionHeader(
                  title: 'Additional Config',
                  subtitle:
                      'Use the generic config editor for non-rollout keys and country-scoped operational settings.',
                ),
                const SizedBox(height: 12),
                if (viewModel.genericConfigs.isEmpty)
                  const EmptyConfigCard(
                    message:
                        'No non-rollout config entries yet. Use the add button to create one.',
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
      builder: (_) => EditConfigSheet(
        config: config,
        ref: ref,
        countries: countries,
      ),
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
      builder: (_) => EditRolloutSheet(
        rollout: rollout,
        ref: ref,
        countries: countries,
      ),
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
