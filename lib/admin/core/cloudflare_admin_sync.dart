import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloudflare/realtime_invalidation.dart';
import '../../core/cloudflare/collect_cloudflare_types.dart';
import 'admin_repository_base.dart';
import 'cloudflare_admin_session.dart';

const _areaPermissions = {
  'profiles': 'users.read',
  'collections': 'collections.read',
  'members': 'users.read',
  'receivers': 'receivers.read',
  'payment_intents': 'payments.read',
  'payments': 'payments.read',
  'ledger': 'ledger.read',
  'reconciliations': 'reconciliations.read',
  'overview': 'overview.read',
  'requests': 'account.manage',
};

Set<String> cloudflareAdminSyncAreas(CloudflareAdminUser? user) =>
    _areaPermissions.entries
        .where((entry) => user?.permissions.contains(entry.value) == true)
        .map((entry) => entry.key)
        .toSet();

/// Polls the shipping HttpOnly-cookie boundary. The shared coordinator retains
/// deduplication, reconnect reconciliation and bounded leading debounce.
class CloudflareAdminSyncSubscription {
  CloudflareAdminSyncSubscription({
    required this.session,
    required void Function() onInvalidate,
    required this.onStatus,
  }) : _fence = session.authorityFence,
       _areas = cloudflareAdminSyncAreas(session.user) {
    _coordinator = CollectSyncInvalidationCoordinator(
      areas: _areas,
      onInvalidate: () {
        if (_current) onInvalidate();
      },
    );
  }
  final CloudflareAdminSession session;
  final void Function(AdminLiveUpdateStatus) onStatus;
  final ({int epoch, Object? key}) _fence;
  final Set<String> _areas;
  late final CollectSyncInvalidationCoordinator _coordinator;
  Timer? _timer;
  bool _disposed = false, _started = false;
  int _failures = 0;
  String _cursor = '0';
  bool get _current =>
      !_disposed &&
      session.mounted &&
      session.authorityFence == _fence &&
      session.user?.expiresAt.isAfter(DateTime.now()) == true;

  void start() {
    if (_started || !_current || _areas.isEmpty) return;
    _started = true;
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (!_current) return;
    var delay = const Duration(seconds: 5);
    try {
      final query = Uri(
        queryParameters: {
          'cursor': _cursor,
          'limit': '100',
          'areas': (_areas.toList()..sort()).join(','),
        },
      ).query;
      final data = await session.request('sync?$query', authenticated: true);
      if (!_current) return;
      final cursor = data['cursor'], events = data['events'];
      final parsed =
          cursor is String && RegExp(r'^(0|[1-9][0-9]{0,15})$').hasMatch(cursor)
          ? BigInt.tryParse(cursor)
          : null;
      if (data['contract_version'] != 1 ||
          parsed == null ||
          parsed > BigInt.from(9007199254740991) ||
          parsed < BigInt.parse(_cursor) ||
          events is! List ||
          events.length > 100 ||
          events.any((row) => !_validEvent(row, parsed))) {
        throw const FormatException('Invalid workspace updates.');
      }
      _coordinator.connectionStatus(CollectSyncStatus.connected);
      onStatus(AdminLiveUpdateStatus.live);
      for (final row in events) {
        _coordinator.event(row as Map<String, dynamic>);
      }
      _cursor = cursor as String;
      _failures = 0;
    } catch (error) {
      if (!_current) return;
      _coordinator.connectionStatus(CollectSyncStatus.disconnected);
      onStatus(AdminLiveUpdateStatus.reconnecting);
      if (error is CloudflareAdminRequestException && error.statusCode == 403) {
        // A grant/role changed during the read. Resolve the current account;
        // provider authority changes dispose this exact departed subscription.
        await session.refresh();
      }
      _failures = (_failures + 1).clamp(1, 5);
      delay = Duration(seconds: (1 << _failures).clamp(5, 60));
    } finally {
      if (_current) _timer = Timer(delay, () => unawaited(_poll()));
    }
  }

  bool _validEvent(Object? row, BigInt cursor) {
    if (row is! Map<String, dynamic> || row.length != 2) return false;
    final id = row['id'], area = row['area'];
    if (id is! String ||
        area is! String ||
        id.length > 100 ||
        !_areas.contains(area) ||
        !RegExp(r'^[1-9][0-9]*:[a-z_]+$').hasMatch(id)) {
      return false;
    }
    final source = id.split(':').first;
    return id == '$source:$area' && BigInt.parse(source) <= cursor;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _coordinator.dispose();
  }
}

final cloudflareAdminSyncSubscriptionProvider = Provider.autoDispose<void>((
  ref,
) {
  final authority = ref.watch(
    cloudflareAdminSessionProvider.select(
      (value) => value.asData?.value?.authorityKey,
    ),
  );
  if (authority == null) return;
  var current = true;
  final subscription = CloudflareAdminSyncSubscription(
    session: ref.read(cloudflareAdminSessionProvider.notifier),
    onStatus: (status) {
      if (current) {
        ref.read(adminLiveUpdateStatusProvider.notifier).state = status;
      }
    },
    onInvalidate: () {
      if (current) ref.read(adminRealtimeTickProvider.notifier).state++;
    },
  )..start();
  ref.onDispose(() {
    current = false;
    subscription.dispose();
  });
});
