import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/models/user_profile.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../config/app_config_provider.dart';
import '../config/app_config_repository.dart';

abstract final class ProductionRedesignRoutes {
  static const rayonHome = 'rayon_home';
  static const rayonShop = 'rayon_shop';
  static const rayonShopCheckout = 'rayon_shop_checkout';
  static const rayonTickets = 'rayon_tickets';
  static const rayonTicketConfirmation = 'rayon_ticket_confirmation';
  static const rayonFanClubs = 'rayon_fan_clubs';
  static const rayonFanClubDetail = 'rayon_fan_club_detail';
  static const rayonMemberRegistry = 'rayon_member_registry';
  static const mobilitySchedule = 'mobility_schedule';
}

class ProductionRedesignScope {
  const ProductionRedesignScope({required this.route, this.partner});

  final String route;
  final String? partner;
}

class ProductionRedesignConfig {
  const ProductionRedesignConfig({
    required this.enabled,
    required this.routeAllowlist,
    required this.partnerAllowlist,
    required this.cohortPercent,
    required this.adminOverride,
  });

  factory ProductionRedesignConfig.defaults() {
    return const ProductionRedesignConfig(
      enabled: true,
      routeAllowlist: <String>{},
      partnerAllowlist: <String>{},
      cohortPercent: 100,
      adminOverride: true,
    );
  }

  factory ProductionRedesignConfig.fromMap(Map<String, String> values) {
    final defaults = ProductionRedesignConfig.defaults();
    return ProductionRedesignConfig(
      enabled: _parseBool(
        values[AppConfigKeys.productionRedesignEnabled],
        fallback: defaults.enabled,
      ),
      routeAllowlist: _parseCsvSet(
        values[AppConfigKeys.productionRedesignRoutes],
      ),
      partnerAllowlist: _parseCsvSet(
        values[AppConfigKeys.productionRedesignPartners],
      ),
      cohortPercent: _parsePercent(
        values[AppConfigKeys.productionRedesignCohortPercent],
        fallback: defaults.cohortPercent,
      ),
      adminOverride: _parseBool(
        values[AppConfigKeys.productionRedesignAdminOverride],
        fallback: defaults.adminOverride,
      ),
    );
  }

  final bool enabled;
  final Set<String> routeAllowlist;
  final Set<String> partnerAllowlist;
  final int cohortPercent;
  final bool adminOverride;

  bool isEnabledFor({
    required ProductionRedesignScope scope,
    required String? userId,
    required bool isAdmin,
  }) {
    if (!enabled) {
      return false;
    }
    if (adminOverride && isAdmin) {
      return true;
    }
    if (routeAllowlist.isNotEmpty && !routeAllowlist.contains(scope.route)) {
      return false;
    }
    final normalizedPartner = scope.partner?.trim().toLowerCase();
    if (partnerAllowlist.isNotEmpty &&
        (normalizedPartner == null ||
            !partnerAllowlist.contains(normalizedPartner))) {
      return false;
    }
    if (cohortPercent >= 100) {
      return true;
    }
    if (cohortPercent <= 0) {
      return false;
    }

    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return false;
    }
    return _stableBucket(normalizedUserId) < cohortPercent;
  }
}

final productionRedesignConfigProvider = Provider<ProductionRedesignConfig>((
  ref,
) {
  try {
    final values = ref.watch(allAppConfigProvider).valueOrNull;
    if (values == null || values.isEmpty) {
      return ProductionRedesignConfig.defaults();
    }
    return ProductionRedesignConfig.fromMap(values);
  } catch (_) {
    return ProductionRedesignConfig.defaults();
  }
});

final productionRedesignEnabledProvider =
    Provider.family<bool, ProductionRedesignScope>((ref, scope) {
      final config = ref.watch(productionRedesignConfigProvider);
      final user = _readCurrentUserSafely(ref);
      return config.isEnabledFor(
        scope: scope,
        userId: user?.id,
        isAdmin: user?.isAdmin ?? false,
      );
    });

UserProfile? _readCurrentUserSafely(Ref ref) {
  try {
    return ref.watch(currentUserProvider);
  } catch (_) {
    return null;
  }
}

Set<String> _parseCsvSet(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>{};
  }
  return raw
      .split(',')
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toSet();
}

bool _parseBool(String? raw, {required bool fallback}) {
  if (raw == null) {
    return fallback;
  }
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}

int _parsePercent(String? raw, {required int fallback}) {
  final parsed = int.tryParse(raw?.trim() ?? '');
  if (parsed == null) {
    return fallback;
  }
  return parsed.clamp(0, 100);
}

int _stableBucket(String input) {
  var hash = 2166136261;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash % 100;
}
