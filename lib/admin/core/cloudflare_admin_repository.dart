import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'admin_repository_base.dart';
import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';
import 'cloudflare_admin_request_identity.dart';
import 'cloudflare_admin_sms_api.dart';
import 'cloudflare_admin_reconciliation_api.dart' show ReconciliationReceipt;

part 'cloudflare_admin_repository_models.dart';
part 'cloudflare_canonical_ledger_contract.dart';
part 'cloudflare_canonical_operating_contract.dart';
part 'cloudflare_admin_repository_operating.dart';
part 'cloudflare_admin_repository_gateway.dart';
part 'cloudflare_admin_repository_email.dart';
part 'cloudflare_admin_repository_member.dart';
part 'cloudflare_admin_repository_notes.dart';

/// Account and operating services use the current Cloudflare schema.
class CloudflareAdminRepository extends AdminRepositoryBase {
  CloudflareAdminRepository(this.session);
  final CloudflareAdminSession session;

  @override
  Future<AdminIdentity?> currentIdentity() async {
    final user = session.user;
    if (user == null) return null;
    return AdminIdentity(
      userId: user.id,
      displayName: user.email,
      roles: [user.role.name == 'owner' ? 'platform_owner' : user.role.name],
      permissions: user.permissions,
    );
  }

  @override
  Future<void> signOut() => session.signOut();

  @override
  Future<AdminRuntimeConfig> runtimeConfig() async => AdminRuntimeConfig(
    useConfiguredNavigationPermissions: true,
    navigationItems: [
      const AdminNavigationItemConfig(
        label: 'Overview',
        iconKey: 'home',
        path: '/admin',
        requiredPermission: 'overview.read',
      ),
      for (final area in CloudflareCoreArea.values)
        AdminNavigationItemConfig(
          label: area.title,
          iconKey: area.iconKey,
          path: area.path,
          requiredPermission: area.permission,
        ),
      const AdminNavigationItemConfig(
        label: 'Reconciliations',
        iconKey: 'reconciliations',
        path: '/admin/reconciliations',
        requiredPermission: 'reconciliations.read',
      ),
      const AdminNavigationItemConfig(
        label: 'SMS receipts',
        iconKey: 'sms',
        path: '/admin/sms-receipts',
        requiredPermission: 'sms.read',
      ),
      if (session.user?.role == AdminAccountRole.owner)
        const AdminNavigationItemConfig(
          label: 'SMS controls',
          iconKey: 'settings',
          path: '/admin/notification-settings',
          requiredPermission: 'admin_users.manage',
        ),
      const AdminNavigationItemConfig(
        label: 'Assisted SMS',
        iconKey: 'sms',
        path: '/admin/notification-operator',
        requiredPermission: 'assisted_sms.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Gateway devices',
        iconKey: 'devices',
        path: '/admin/gateway',
        requiredPermission: 'gateway.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Member receipts',
        iconKey: 'receipt_long',
        path: '/admin/member-receipts',
        requiredPermission: 'payments.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Email notifications',
        iconKey: 'mail',
        path: '/admin/email',
        requiredPermission: 'email.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Request history',
        iconKey: 'history',
        path: '/admin/requests',
        requiredPermission: 'overview.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Privacy requests',
        iconKey: 'privacy',
        path: '/admin/privacy-requests',
        requiredPermission: 'privacy.review',
      ),
      const AdminNavigationItemConfig(
        label: 'Admins and staff',
        iconKey: 'admin_panel_settings',
        path: '/admin/admin-users',
        requiredPermission: 'admin_users.read',
      ),
      const AdminNavigationItemConfig(
        label: 'Password and security',
        iconKey: 'settings',
        path: '/admin/security',
        requiredPermission: 'account.manage',
      ),
    ],
    queueSpecs: [],
  );

  Never _unavailable() => throw UnsupportedError(
    'This part of your workspace is not yet available.',
  );

  @override
  Future<void> sendOtp({required String phone}) async => _unavailable();
  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async => _unavailable();
  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    final result = await _read('core/overview', 'overview.read');
    if (result.containsKey('contract_version') || result.containsKey('model')) {
      return _canonicalOverviewMetrics(result);
    }
    const fields = {
      'country_code',
      'measured_at',
      'counts',
      'amounts',
      'metrics',
      'contribution_basis',
      'collected_basis',
      'reconciliations_available',
    };
    if (result.length != fields.length ||
        !result.keys.every(fields.contains) ||
        result['country_code'] != 'RW' ||
        !_coreTimestamp(result['measured_at']) ||
        result['counts'] is! Map ||
        result['amounts'] is! Map ||
        result['contribution_basis'] != 'confirmation_recorded_allocations' ||
        result['collected_basis'] != 'confirmation_recorded_transactions' ||
        result['reconciliations_available'] is! bool ||
        result['metrics'] is! List) {
      _invalidCore();
    }
    final counts = result['counts'] as Map;
    final amounts = result['amounts'] as Map;
    final metrics = result['metrics'] as List;
    if (counts.length != _coreMetricLabels.length ||
        !counts.keys.every(_coreMetricLabels.containsKey) ||
        counts.values.any(
          (value) => value is! int || value < 0 || value > _maximumExactInteger,
        ) ||
        amounts.length != _coreAmountLabels.length ||
        !amounts.keys.every(_coreAmountLabels.containsKey) ||
        !amounts.values.every(_decimalAmount) ||
        metrics.length != _coreMetricLabels.length + _coreAmountLabels.length) {
      _invalidCore();
    }
    final labels = {..._coreMetricLabels, ..._coreAmountLabels};
    final seen = <String>{};
    for (final metric in metrics) {
      if (metric is! Map ||
          metric.length != 4 ||
          !labels.containsKey(metric['key']) ||
          labels[metric['key']] != metric['label'] ||
          metric['status'] != 'measured' ||
          metric['value'] is! String ||
          !seen.add(metric['key'] as String)) {
        _invalidCore();
      }
      final key = metric['key'] as String;
      if (metric['value'] != '${counts[key] ?? amounts[key]}') _invalidCore();
    }
    return List.unmodifiable([
      for (final entry in labels.entries)
        AdminMetric(
          label: entry.value,
          value: '${counts[entry.key] ?? amounts[entry.key]}',
          status: 'measured',
          sourceModel: 'transaction_journals',
        ),
    ]);
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    final areas = CloudflareCoreArea.values.where(
      (area) => area.rpcName == rpcName,
    );
    if (areas.isEmpty) return _unavailable();
    final area = areas.single;
    final size = limit ?? 25;
    final start = offset ?? 0;
    final query = search?.trim() ?? '';
    final state = status?.trim() ?? '';
    final order = sortBy?.trim() ?? 'created_at_desc';
    final country = countryCode?.trim().toUpperCase() ?? 'RW';
    if (size < 1 ||
        size > 100 ||
        start < 0 ||
        start > 2147483647 ||
        query.length > 200 ||
        country != 'RW' ||
        (state.isNotEmpty && !area.acceptsStatus(state)) ||
        !area.acceptsSort(order)) {
      throw const FormatException('The workspace filters are invalid.');
    }
    final parameters = Uri(
      queryParameters: {
        'search': query,
        'status': state,
        'limit': '$size',
        'offset': '$start',
        'sort': order,
        'country': country,
      },
    ).query;
    final result = await _read(
      'core/${area.name}?$parameters',
      area.permission,
    );
    final canonical =
        result.containsKey('contract_version') || result.containsKey('model');
    final fields = canonical
        ? const {'contract_version', 'model', 'rows', 'total'}
        : const {'rows', 'total'};
    if (result.length != fields.length ||
        !result.keys.every(fields.contains) ||
        (canonical &&
            (result['contract_version'] != 2 ||
                result['model'] != 'canonical_evidence_ledger')) ||
        result['rows'] is! List ||
        result['total'] is! int) {
      _invalidCore();
    }
    final statuses = canonical ? area.canonicalStatuses : area.statuses;
    for (final row in result['rows'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          !_coreUuid.hasMatch(row['id'] as String) ||
          row['title'] is! String ||
          (row['title'] as String).trim().isEmpty ||
          row['subtitle'] is! String ||
          row['amount'] is! String ||
          !statuses.contains(row['status']) ||
          (state.isNotEmpty && row['status'] != state) ||
          row['country_code'] != 'RW' ||
          row['currency_code'] != 'RWF' ||
          !_coreTimestamp(row['created_at'])) {
        _invalidCore();
      }
      if (canonical) {
        _validateCanonicalCoreRow(area, row);
      } else {
        _validateCoreRow(area, row);
      }
    }
    final parsed = AdminListResult.fromJson(result);
    return AdminListResult(
      rows: parsed.rows,
      total: parsed.total,
      sourceModel: canonical
          ? 'canonical_evidence_ledger'
          : 'transaction_journals',
    ).validateWindow(limit: size, offset: start);
  }

  CloudflareAdminUser _requirePermission(String permission) {
    final user = session.user;
    if (user == null || !user.expiresAt.isAfter(DateTime.now())) {
      throw const AdminAccountException('Sign in again to continue.');
    }
    if (!user.permissions.contains(permission)) {
      throw const AdminAccountException(
        'You do not have permission to view these records.',
      );
    }
    return user;
  }

  Future<Map<String, dynamic>> _read(String path, String permission) async {
    final before = _requirePermission(permission);
    final result = await session.request(path, authenticated: true);
    final after = _requirePermission(permission);
    if (after.id != before.id || after.sessionId != before.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Reopen this page before continuing.',
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async =>
      _unavailable();
  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async => _unavailable();
}
