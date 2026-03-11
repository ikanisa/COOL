import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Polls a Supabase table for status changes on a specific record.
///
/// Used after USSD payment launch to detect when `parse-momo-sms`
/// confirms the payment. The provider automatically cancels polling
/// when the status leaves 'pending' or after timeout.
///
/// Usage:
/// ```dart
/// final status = ref.watch(paymentStatusProvider(PaymentPollArgs(
///   table: 'rs_tickets',
///   recordId: ticketId,
///   statusColumn: 'status',
/// )));
/// ```
class PaymentPollArgs {
  const PaymentPollArgs({
    required this.table,
    required this.recordId,
    this.statusColumn = 'status',
    this.pollIntervalSeconds = 5,
    this.timeoutSeconds = 300,
  });

  final String table;
  final String recordId;
  final String statusColumn;
  final int pollIntervalSeconds;
  final int timeoutSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentPollArgs &&
          table == other.table &&
          recordId == other.recordId;

  @override
  int get hashCode => Object.hash(table, recordId);
}

/// Possible outcomes of a payment poll.
enum PaymentPollStatus { polling, confirmed, failed, timeout }

class PaymentPollState {
  const PaymentPollState({
    this.status = PaymentPollStatus.polling,
    this.dbStatus,
    this.errorMessage,
  });

  final PaymentPollStatus status;
  final String? dbStatus;
  final String? errorMessage;

  bool get isPolling => status == PaymentPollStatus.polling;
  bool get isConfirmed => status == PaymentPollStatus.confirmed;
  bool get isFailed => status == PaymentPollStatus.failed;
  bool get isTimeout => status == PaymentPollStatus.timeout;
}

final paymentStatusProvider = StateNotifierProvider.autoDispose
    .family<PaymentStatusNotifier, PaymentPollState, PaymentPollArgs>(
  (ref, args) {
    final notifier = PaymentStatusNotifier(args);
    ref.onDispose(notifier.dispose);
    return notifier;
  },
);

class PaymentStatusNotifier extends StateNotifier<PaymentPollState> {
  PaymentStatusNotifier(this._args) : super(const PaymentPollState()) {
    _startPolling();
  }

  final PaymentPollArgs _args;
  Timer? _timer;
  DateTime? _startedAt;
  bool _disposed = false;

  /// Statuses that mean the payment has been confirmed.
  static const _confirmedStatuses = {'valid', 'confirmed', 'paid'};

  /// Statuses that mean the payment definitively failed.
  static const _failedStatuses = {'failed', 'cancelled'};

  void _startPolling() {
    _startedAt = DateTime.now();
    _poll(); // immediate first check
    _timer = Timer.periodic(
      Duration(seconds: _args.pollIntervalSeconds),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    if (_disposed) return;

    // Check timeout
    final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
    if (elapsed >= _args.timeoutSeconds) {
      _stopPolling();
      debugPrint(
        '[PaymentPoll] ⏱️ TIMEOUT after ${elapsed}s '
        '(table=${_args.table}, id=${_args.recordId})',
      );
      if (mounted) {
        state = const PaymentPollState(status: PaymentPollStatus.timeout);
      }
      return;
    }

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from(_args.table)
          .select(_args.statusColumn)
          .eq('id', _args.recordId)
          .maybeSingle();

      if (_disposed) return;

      final dbStatus =
          (response?[_args.statusColumn] as String?)?.toLowerCase();

      if (dbStatus == null) return; // record not found yet

      if (_confirmedStatuses.contains(dbStatus)) {
        _stopPolling();
        debugPrint(
          '[PaymentPoll] ✅ CONFIRMED (dbStatus=$dbStatus, '
          'elapsed=${elapsed}s, table=${_args.table}, '
          'id=${_args.recordId})',
        );
        state = PaymentPollState(
          status: PaymentPollStatus.confirmed,
          dbStatus: dbStatus,
        );
      } else if (_failedStatuses.contains(dbStatus)) {
        _stopPolling();
        debugPrint(
          '[PaymentPoll] ❌ FAILED (dbStatus=$dbStatus, '
          'elapsed=${elapsed}s, table=${_args.table}, '
          'id=${_args.recordId})',
        );
        state = PaymentPollState(
          status: PaymentPollStatus.failed,
          dbStatus: dbStatus,
        );
      }
      // else: still pending, keep polling
    } catch (e) {
      debugPrint('[PaymentPoll] ⚠️ Poll error (non-fatal): $e');
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
