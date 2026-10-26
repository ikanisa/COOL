import '../shared/components/admin_data_listing.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'admin_automatic_gateway_models.dart';
import 'admin_auth_guard.dart';
import 'admin_models.dart';
import 'admin_display_formatters.dart';
import 'admin_entity_audit.dart';
import 'admin_receipt_operational_history_models.dart';
import 'admin_runtime.dart';

bool _canRead(AdminIdentity? identity) =>
    identity?.permissions.contains('notifications.read') == true &&
    identity?.permissions.contains('system_health.read') == true;

String _time(DateTime at) =>
    '${adminKigaliDate(at)} · ${adminKigaliTime(at)}:${at.second.toString().padLeft(2, '0')} · Africa/Kigali';

/// Evidence readers do not expose a send, retry, archive or recovery mutation.
class AdminAutomaticReceiptCard extends ConsumerStatefulWidget {
  const AdminAutomaticReceiptCard({required this.receiptId, super.key});
  final String receiptId;
  @override
  ConsumerState<AdminAutomaticReceiptCard> createState() => _ReceiptState();
}

class _ReceiptState extends ConsumerState<AdminAutomaticReceiptCard> {
  AdminAutomaticHistoryCursor? _cursor;
  final _previous = <AdminAutomaticHistoryCursor?>[];
  Object? _scope;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AdminAutomaticReceiptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiptId != widget.receiptId) {
      _cursor = null;
      _previous.clear();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(adminAuthSessionScopeProvider);
    if (_scope != scope) {
      _scope = scope;
      _cursor = null;
      _previous.clear();
    }
    final identity = ref.watch(adminIdentityProvider);
    if (identity.isLoading) {
      return const _Notice(
        'Automatic send evidence',
        'Checking gateway read access.',
      );
    }
    if (!_canRead(identity.valueOrNull)) {
      return const _Notice(
        'Automatic send evidence access required',
        'Notification and system health read permissions are required.',
      );
    }
    final query = (receiptId: widget.receiptId, limit: 20, before: _cursor);
    final read = ref.watch(adminAutomaticReceiptProvider(query));
    final now = ref.watch(adminClockProvider)();
    return _Panel(
      title: 'Automatic send evidence',
      children: [
        read.when(
          skipLoadingOnRefresh: false,
          loading: () => const _Notice(
            'Loading automatic send evidence',
            'Reading the current attempt and retained framework observations.',
          ),
          error: (error, _) => _ReadError(error),
          data: (data) {
            if (!data.isFresh(now)) {
              return const _Notice(
                'Automatic evidence expired',
                'Refresh to read current evidence. Previous attempt and callback observations are hidden.',
              );
            }
            if (data.status == 'unavailable') {
              return const _Notice(
                'Automatic evidence unavailable',
                'Current supported receipt scope could not be established.',
              );
            }
            if (data.status == 'no_automatic_attempt') {
              return const _Notice(
                'No automatic attempt recorded',
                'No automatic grant is recorded for this receipt. Assisted transport evidence remains separate.',
              );
            }
            final attempt = data.attempt!;
            final arm = data.arm;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Checked ${_time(data.checkedAt)}'),
                const SizedBox(height: 8),
                _Attempt(
                  attempt,
                  checkedAt: data.checkedAt,
                  validUntil: data.validUntil,
                ),
                const SizedBox(height: 12),
                if (arm == null)
                  const Text(
                    'No final arm recorded. A historical grant does not authorize a send now.',
                  )
                else ...[
                  const _Heading('Final arm'),
                  SelectableText('Request ${arm.requestId}'),
                  Text(
                    'Armed ${_time(arm.armedAt)} · Expired/ends ${_time(arm.expiresAt)}',
                  ),
                  SelectableText(
                    'Health observation ${arm.healthObservationId}',
                  ),
                ],
                const SizedBox(height: 12),
                const _Heading('Multipart framework callbacks'),
                if (data.expectedCallbacks.isEmpty)
                  const Text('No callback plan is recorded.'),
                for (final callback in data.expectedCallbacks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Segment ${callback.segmentIndex + 1}/${attempt.segmentCount} · ${callback.kind} · ${!callback.hasObservation
                              ? 'not recorded'
                              : callback.consistent
                              ? 'consistent observations'
                              : 'conflicting observations'}',
                        ),
                        SelectableText(callback.id),
                        if (callback.hasObservation)
                          Text(
                            'Result ${callback.resultCode} · TP status ${callback.tpStatus ?? 'not supplied'}',
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const _Heading('Historical archive acknowledgement'),
                if (data.archiveAck == null)
                  const Text('No terminal archive acknowledgement is recorded.')
                else ...[
                  SelectableText('Acknowledgement ${data.archiveAck!.id}'),
                  SelectableText('Request ${data.archiveAck!.requestId}'),
                  Text('Recorded ${_time(data.archiveAck!.recordedAt)}'),
                  const Text(
                    'This acknowledged complete framework observations at that time. Later contradictions remain visible above.',
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Framework observations and archival evidence do not establish carrier delivery or authorize another send.',
                ),
                const SizedBox(height: 16),
                const _Heading('Retained request history'),
                const Text(
                  'Historical coverage is incomplete. This page does not attest an exhaustive timeline.',
                ),
                for (final row in data.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_time(row.recordedAt)} · ${row.source}'),
                        SelectableText('Request ${row.requestId}'),
                        if (row.source == 'callback')
                          Text(
                            'Segment ${row.segmentIndex! + 1} · ${row.callbackKind} · result ${row.resultCode}',
                          ),
                        if (row.occurredAt != null)
                          Text('Handset timestamp ${_time(row.occurredAt!)}'),
                        if (row.code != null)
                          Text(
                            row.code == 'ORIGINAL_REQUEST_RECORDED'
                                ? 'Original authority request retained; no replay authority.'
                                : row.code!,
                          ),
                      ],
                    ),
                  ),
                _Pages(
                  previous: _previous.isEmpty
                      ? null
                      : () => setState(() => _cursor = _previous.removeLast()),
                  next: data.nextCursor == null
                      ? null
                      : () => setState(() {
                          _previous.add(_cursor);
                          _cursor = data.nextCursor;
                        }),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: read.isLoading
                ? null
                : () => ref.invalidate(adminAutomaticReceiptProvider(query)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh automatic evidence'),
          ),
        ),
      ],
    );
  }
}

class AdminAutomaticDeviceCard extends ConsumerStatefulWidget {
  const AdminAutomaticDeviceCard({required this.deviceId, super.key});
  final String deviceId;
  @override
  ConsumerState<AdminAutomaticDeviceCard> createState() => _DeviceState();
}

class _DeviceState extends ConsumerState<AdminAutomaticDeviceCard> {
  AdminAutomaticDeviceCursor? _cursor;
  final _previous = <AdminAutomaticDeviceCursor?>[];
  Object? _scope;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AdminAutomaticDeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _cursor = null;
      _previous.clear();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(adminAuthSessionScopeProvider);
    if (_scope != scope) {
      _scope = scope;
      _cursor = null;
      _previous.clear();
    }
    final identity = ref.watch(adminIdentityProvider);
    if (identity.isLoading) {
      return const _Notice(
        'Automatic attempts',
        'Checking gateway read access.',
      );
    }
    if (!_canRead(identity.valueOrNull)) {
      return const _Notice(
        'Automatic attempt access required',
        'Notification and system health read permissions are required.',
      );
    }
    final query = (deviceId: widget.deviceId, limit: 20, before: _cursor);
    final read = ref.watch(adminAutomaticDeviceProvider(query));
    final now = ref.watch(adminClockProvider)();
    return _Panel(
      title: 'Automatic attempts',
      children: [
        read.when(
          skipLoadingOnRefresh: false,
          loading: () => const _Notice(
            'Loading automatic attempts',
            'Reading retained device attempts.',
          ),
          error: (error, _) => _ReadError(error),
          data: (data) {
            if (!data.isFresh(now)) {
              return const _Notice(
                'Automatic attempts expired',
                'Refresh for current evidence. Previous attempts are hidden.',
              );
            }
            if (data.status == 'unavailable') {
              return const _Notice(
                'Device unavailable',
                'The device is unavailable to the current read.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Checked ${_time(data.checkedAt)}'),
                const Text(
                  'Current supported receipt scope only. Historical coverage is incomplete.',
                ),
                if (data.rows.isEmpty)
                  Text(
                    data.nextCursor != null
                        ? 'No visible attempts in this page. Continue to check older evidence.'
                        : 'No visible automatic attempts in this page.',
                  ),
                for (final attempt in data.rows) ...[
                  const SizedBox(height: 12),
                  _Attempt(
                    attempt,
                    checkedAt: data.checkedAt,
                    validUntil: data.validUntil,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(
                        '/admin/sms-receipts/${attempt.receiptId}',
                      ),
                      child: const Text('Open receipt evidence'),
                    ),
                  ),
                ],
                _Pages(
                  previous: _previous.isEmpty
                      ? null
                      : () => setState(() => _cursor = _previous.removeLast()),
                  // An empty filtered page can still have a scanned-window cursor.
                  next: data.nextCursor == null
                      ? null
                      : () => setState(() {
                          _previous.add(_cursor);
                          _cursor = data.nextCursor;
                        }),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: read.isLoading
                ? null
                : () => ref.invalidate(adminAutomaticDeviceProvider(query)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh automatic attempts'),
          ),
        ),
      ],
    );
  }
}

class _Attempt extends ConsumerWidget {
  const _Attempt(
    this.attempt, {
    required this.checkedAt,
    required this.validUntil,
  });
  final AdminAutomaticAttempt attempt;
  final DateTime checkedAt, validUntil;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = AdminReceiptOperationalHistoryNavigationScope(ref);
    bool current() {
      final now = ref.read(adminClockProvider)().toUtc();
      return navigation.isCurrent &&
          !now.isBefore(checkedAt) &&
          now.isBefore(validUntil);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recorded state: ${attempt.state}'),
        SelectableText('Attempt ${attempt.id}'),
        SelectableText('Run ${attempt.runId}'),
        if (current())
          TextButton(
            onPressed: () {
              if (current()) {
                context.push(adminReceiptOperationalRunPath(attempt.runId));
              }
            },
            child: const Text('Open operational run evidence'),
          ),
        SelectableText('Principal ${attempt.principalId}'),
        Text(
          'Fence ${attempt.fence} · Policy ${attempt.policyRevision} · Segments ${attempt.segmentCount}',
        ),
        Text(
          'Granted ${_time(attempt.issuedAt)} · Grant ends ${_time(attempt.expiresAt)}',
        ),
        Text('State updated ${_time(attempt.updatedAt)}'),
        SelectableText('Grant request ${attempt.grantRequestId}'),
        SelectableText(
          'Grant health observation ${attempt.healthObservationId}',
        ),
        AdminEntityAuditLink(
          kind: AdminAuditEntityKind.receipt,
          id: attempt.receiptId,
        ),
        AdminEntityAuditLink(
          kind: AdminAuditEntityKind.gatewayDevice,
          id: attempt.deviceId,
        ),
      ],
    );
  }
}

class _ReadError extends StatelessWidget {
  const _ReadError(this.error);
  final Object error;
  @override
  Widget build(BuildContext context) => _Notice(
    error is AdminGatewayDenied
        ? 'Automatic evidence access denied'
        : error is AdminSessionChanged
        ? 'Admin session changed'
        : error is UnsupportedError
        ? 'Automatic evidence unavailable'
        : 'Automatic evidence read failed',
    error is AdminSessionChanged
        ? 'Reopen the detail with the current Admin session.'
        : 'Evidence could not be authorized, loaded or validated. Refresh the read to investigate.',
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.title, this.message);
  final String title, message;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_Heading(title), const SizedBox(height: 8), Text(message)],
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AdminDataSection(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_Heading(title), const SizedBox(height: 12), ...children],
      ),
    ),
  );
}

class _Pages extends StatelessWidget {
  const _Pages({this.previous, this.next});
  final VoidCallback? previous, next;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: previous,
          child: const Text('Previous evidence'),
        ),
        OutlinedButton(onPressed: next, child: const Text('Older evidence')),
      ],
    ),
  );
}
