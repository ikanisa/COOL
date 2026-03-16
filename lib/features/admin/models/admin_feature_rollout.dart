import '../../../core/config/app_market.dart';
import '../../../core/models/engagement_feature_flags.dart';

class AdminFeatureRolloutConfig {
  const AdminFeatureRolloutConfig({
    required this.key,
    required this.label,
    required this.description,
    required this.killSwitchKey,
    required this.rollout,
  });

  final String key;
  final String label;
  final String description;
  final String killSwitchKey;
  final ManagedFeatureRollout rollout;

  static const List<_ManagedFeatureSpec> _specs = <_ManagedFeatureSpec>[
    _ManagedFeatureSpec(
      key: 'momo',
      label: 'Mobile Money',
      description:
          'Control MoMo payments and',
      killSwitchKey: 'kill_momo_payments',
    ),
    _ManagedFeatureSpec(
      key: 'credit',
      label: 'Credit',
      description:
          'Stage lending readiness score',
      killSwitchKey: 'kill_credit_features',
    ),
    _ManagedFeatureSpec(
      key: 'ticket_purchase',
      label: 'Ticketing',
      description:
          'Gate Rayon Sports ticket',
      killSwitchKey: 'kill_ticket_purchase',
    ),
    _ManagedFeatureSpec(
      key: 'mobility',
      label: 'Mobility',
      description:
          'Roll out rider and',
      killSwitchKey: 'kill_mobility',
    ),
  ];

  static final Set<String> managedConfigKeys = <String>{
    for (final spec in _specs) spec.killSwitchKey,
    for (final spec in _specs) 'feature_${spec.key}_stage',
    for (final spec in _specs) 'feature_${spec.key}_admin_only',
  };
  static final RegExp _legacyManagedConfigKeyPattern = RegExp(
    r'^feature_[a-z_]+_allowed_[a-z_]+$',
  );

  static bool isManagedFeatureConfigKey(String key) {
    final normalized = key.trim();
    return managedConfigKeys.contains(normalized) ||
        _legacyManagedConfigKeyPattern.hasMatch(normalized);
  }

  static List<AdminFeatureRolloutConfig> fromAppConfigEntries(
    List<Map<String, dynamic>> entries,
  ) {
    final defaults = EngagementFeatureFlags.defaults();
    final values = <String, Object?>{};
    for (final entry in entries) {
      final key = entry['key']?.toString().trim();
      final country = entry['country']?.toString().trim();
      if (key == null || key.isEmpty || !isManagedFeatureConfigKey(key)) {
        continue;
      }
      if (country != null &&
          country.isNotEmpty &&
          country != AppMarket.countryCode) {
        continue;
      }
      values[key] = entry['value'];
    }

    return _specs
        .map((spec) {
          return AdminFeatureRolloutConfig(
            key: spec.key,
            label: spec.label,
            description: spec.description,
            killSwitchKey: spec.killSwitchKey,
            rollout: ManagedFeatureRollout.fromValues(
              key: spec.key,
              killSwitchKey: spec.killSwitchKey,
              values: values,
              fallback: _defaultRollout(defaults, spec.key),
            ),
          );
        })
        .toList(growable: false);
  }

  AdminFeatureRolloutConfig copyWith({ManagedFeatureRollout? rollout}) {
    return AdminFeatureRolloutConfig(
      key: key,
      label: label,
      description: description,
      killSwitchKey: killSwitchKey,
      rollout: rollout ?? this.rollout,
    );
  }

  List<Map<String, dynamic>> toAppConfigEntries() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'key': killSwitchKey,
        'value': rollout.killSwitch.toString(),
        'description': 'Emergency kill switch for $label.',
        'country': AppMarket.countryCode,
      },
      <String, dynamic>{
        'key': 'feature_${key}_stage',
        'value': rollout.stage.remoteConfigValue,
        'description': 'Rollout stage for $label.',
        'country': AppMarket.countryCode,
      },
      <String, dynamic>{
        'key': 'feature_${key}_admin_only',
        'value': rollout.adminOnly.toString(),
        'description': 'Require admin access for $label.',
        'country': AppMarket.countryCode,
      },
    ];
  }

  static ManagedFeatureRollout _defaultRollout(
    EngagementFeatureFlags defaults,
    String key,
  ) {
    switch (key) {
      case 'momo':
        return defaults.momo;
      case 'credit':
        return defaults.credit;
      case 'ticket_purchase':
        return defaults.ticketPurchase;
      case 'mobility':
        return defaults.mobility;
    }
    throw StateError('Unsupported managed feature key: $key');
  }
}

class _ManagedFeatureSpec {
  const _ManagedFeatureSpec({
    required this.key,
    required this.label,
    required this.description,
    required this.killSwitchKey,
  });

  final String key;
  final String label;
  final String description;
  final String killSwitchKey;
}
