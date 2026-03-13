part of '../screens/manage_app_config_screen.dart';

class ManageAppConfigViewModel {
  const ManageAppConfigViewModel({
    required this.rollouts,
    required this.mobilitySubscriptionConfigs,
    required this.genericConfigs,
  });

  final List<AdminFeatureRolloutConfig> rollouts;
  final List<Map<String, dynamic>> mobilitySubscriptionConfigs;
  final List<Map<String, dynamic>> genericConfigs;

  factory ManageAppConfigViewModel.fromEntries(
    List<Map<String, dynamic>> configs,
  ) {
    final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(configs);
    final mobilitySubscriptionConfigs =
        configs
            .where(
              (entry) =>
                  entry['key'] == AppConfigKeys.mobilitySubscriptionMomoCode,
            )
            .toList()
          ..sort((left, right) {
            final leftCountry =
                left['country']?.toString().trim().toUpperCase() ?? '';
            final rightCountry =
                right['country']?.toString().trim().toUpperCase() ?? '';
            if (leftCountry.isEmpty != rightCountry.isEmpty) {
              return leftCountry.isEmpty ? -1 : 1;
            }
            return leftCountry.compareTo(rightCountry);
          });
    final genericConfigs =
        configs.where((entry) {
          final key = entry['key']?.toString();
          final country = entry['country']?.toString().trim();
          if (key == null || key.isEmpty) {
            return false;
          }
          if (key == AppConfigKeys.mobilitySubscriptionMomoCode) {
            return false;
          }
          if (!AdminFeatureRolloutConfig.isManagedFeatureConfigKey(key)) {
            return true;
          }
          return country != null && country.isNotEmpty;
        }).toList()
          ..sort((left, right) {
            final leftKey = left['key']?.toString() ?? '';
            final rightKey = right['key']?.toString() ?? '';
            return leftKey.compareTo(rightKey);
          });

    return ManageAppConfigViewModel(
      rollouts: rollouts,
      mobilitySubscriptionConfigs: mobilitySubscriptionConfigs,
      genericConfigs: genericConfigs,
    );
  }
}
