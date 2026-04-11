import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/models/engagement_feature_flags.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/admin_feature_rollout.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';

part '../controllers/manage_app_config_view_model.dart';
part '../widgets/manage_app_config_sections.dart';
part '../widgets/manage_app_config_sheets.dart';
part '../widgets/manage_app_config_edit_sheets.dart';

EdgeInsets _appConfigListPadding() =>
    const EdgeInsets.only(bottom: CoolSpace.x7);

EdgeInsets _appConfigSectionSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _appConfigTileSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x2,
);

const BorderRadius _appConfigActionRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

/// Admin screen for managing key-value app configuration.
class ManageAppConfigScreen extends ConsumerWidget {
  const ManageAppConfigScreen({super.key});

  Future<T?> _showAdminEditor<T>(BuildContext context, WidgetBuilder builder) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, _) => Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: builder(dialogContext),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final configAsync = ref.watch(adminAppConfigProvider);
    final partnerRoutesAsync = ref.watch(adminPartnerPaymentRoutesProvider);
    final partnersAsync = ref.watch(adminPartnersProvider);
    final countries = ref.watch(supportedCountriesProvider);

    return AdminDetailScaffold(
      title: Text(
        'App Config',
        style: theme.textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      subtitle: Text(
        context.l10n.rolloutGovernance,
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.coolSemanticColors.secondaryText,
          fontWeight: FontWeight.w500,
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: context.l10n.addConfigEntry,
        hint: 'New config',
        child: FloatingActionButton(
          backgroundColor: context.coolSemanticColors.accent,
          onPressed: () => _showEditSheet(context, ref, null, countries),
          child: Icon(CoolIcons.add, color: theme.colorScheme.onPrimary),
        ),
      ),
      child: CoolAsyncView<List<Map<String, dynamic>>>(
        value: configAsync,
        onRetry: () => ref.invalidate(adminAppConfigProvider),
        emptyCheck: (_) => false,
        builder: (configs) {
          final colors = context.coolSemanticColors;
          final viewModel = ManageAppConfigViewModel.fromEntries(configs);
          final partnerRoutes = partnerRoutesAsync.valueOrNull ?? const [];
          final partners = partnersAsync.valueOrNull ?? const [];
          return ListView(
            padding: _appConfigListPadding(),
            children: [
              const SizedBox(height: CoolSpace.x1),
              ...viewModel.rollouts.map(
                (rollout) => Padding(
                  padding: _appConfigSectionSpacing(),
                  child: RolloutCard(
                    rollout: rollout,
                    onEdit: () =>
                        _showRolloutSheet(context, ref, rollout, countries),
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              const AppConfigSectionHeader(
                title: 'Partner Payment Routes',
                message: 'Manage Rwanda partner checkout',
              ),
              const SizedBox(height: CoolSpace.x3),
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
                    foregroundColor: colors.primaryText,
                    side: BorderSide.none,
                    backgroundColor: colors.buttonSecondaryBackground,
                    shape: const RoundedRectangleBorder(
                      borderRadius: _appConfigActionRadius,
                    ),
                  ),
                  icon: const Icon(CoolIcons.add, size: 18),
                  label: Text(
                    'Add route',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              if (partnerRoutesAsync.isLoading && partnerRoutes.isEmpty)
                const EmptyConfigCard(
                  message: 'Loading partner payment routes…',
                )
              else if (partnerRoutesAsync.hasError)
                const EmptyConfigCard(message: 'Load partner payment failed')
              else if (partnerRoutes.isEmpty)
                const EmptyConfigCard(message: 'No partner payment routes')
              else
                ...partnerRoutes.map(
                  (route) => Padding(
                    padding: _appConfigTileSpacing(),
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
              const SizedBox(height: CoolSpace.x3),
              const AppConfigSectionHeader(
                title: 'Additional Config',
                message: 'Use the generic config',
              ),
              const SizedBox(height: CoolSpace.x3),
              if (viewModel.genericConfigs.isEmpty)
                const EmptyConfigCard(message: 'No non-rollout config entries')
              else
                ...viewModel.genericConfigs.map(
                  (config) => Padding(
                    padding: _appConfigTileSpacing(),
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
    _showAdminEditor<void>(
      context,
      (_) => EditPartnerPaymentRouteSheet(
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
    _showAdminEditor<void>(
      context,
      (_) => EditConfigSheet(config: config, ref: ref, countries: countries),
    );
  }

  void _showRolloutSheet(
    BuildContext context,
    WidgetRef ref,
    AdminFeatureRolloutConfig rollout,
    List<CoolCountry> countries,
  ) {
    _showAdminEditor<void>(
      context,
      (_) => EditRolloutSheet(rollout: rollout, ref: ref, countries: countries),
    );
  }
}
