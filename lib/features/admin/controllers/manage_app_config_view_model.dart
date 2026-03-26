part of '../screens/manage_app_config_screen.dart';

class ManageAppConfigViewModel {
  const ManageAppConfigViewModel({
    required this.rollouts,
    required this.genericConfigs,
  });

  final List<AdminFeatureRolloutConfig> rollouts;
  final List<Map<String, dynamic>> genericConfigs;

  factory ManageAppConfigViewModel.fromEntries(
    List<Map<String, dynamic>> configs,
  ) {
    final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(configs);
    final genericConfigs =
        configs.where((entry) {
          final key = entry['key']?.toString();
          if (key == null || key.isEmpty) {
            return false;
          }
          return !AdminFeatureRolloutConfig.isManagedFeatureConfigKey(key);
        }).toList()..sort((left, right) {
          final leftKey = left['key']?.toString() ?? '';
          final rightKey = right['key']?.toString() ?? '';
          return leftKey.compareTo(rightKey);
        });

    return ManageAppConfigViewModel(
      rollouts: rollouts,
      genericConfigs: genericConfigs,
    );
  }
}
