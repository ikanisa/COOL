import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/sms_access_channel.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../env/app_env.dart';

/// Runs in Android builds that enable Rwanda MoMo receipt reconciliation.
/// Access remains off until an authenticated Rwanda member gives consent.
class MemberSmsReceiptHost extends ConsumerStatefulWidget {
  const MemberSmsReceiptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MemberSmsReceiptHost> createState() =>
      _MemberSmsReceiptHostState();
}

class _MemberSmsReceiptHostState extends ConsumerState<MemberSmsReceiptHost>
    with WidgetsBindingObserver {
  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  StreamSubscription<void>? _subscription;
  Future<int>? _syncInFlight;
  MemberSmsIntakeSession? _syncSession;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _syncRequested = false;
  bool _foreground = true;
  late final bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled =
        ref.read(appEnvProvider).enableAndroidSmsAccess &&
        ref.read(momoReceiptCaptureAvailableProvider);
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = const SmsAccessChannel().pendingSmsEvents.listen(
      (_) => _sync(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    if (_enabled) WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _sync();
    }
  }

  void _sync({bool newSignal = true}) {
    if (!_enabled || !_foreground || !mounted) return;
    if (newSignal) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
    }
    final session = ref.read(memberSmsIntakeSessionProvider);
    if (_syncInFlight != null && _syncSession == session) {
      _syncRequested = true;
      return;
    }
    _syncRequested = false;
    final sync = session.intake.syncPendingSmsAccess();
    _syncSession = session;
    _syncInFlight = sync;
    unawaited(
      sync.then<void>(
        (_) => _finishSync(sync, session, failed: false),
        onError: (Object _, StackTrace _) =>
            _finishSync(sync, session, failed: true),
      ),
    );
  }

  void _finishSync(
    Future<int> sync,
    MemberSmsIntakeSession session, {
    required bool failed,
  }) {
    if (!identical(_syncInFlight, sync) || _syncSession != session) return;
    _syncInFlight = null;
    _syncSession = null;
    if (!mounted || !_enabled) return;
    final current = ref.read(memberSmsIntakeSessionProvider);
    if (current != session) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
      _syncRequested = false;
      if (current.ownerId != null) _sync();
      return;
    }
    if (_syncRequested) {
      _syncRequested = false;
      _sync();
      return;
    }
    if (!failed) {
      _retryAttempt = 0;
      return;
    }
    if (!_foreground || current.ownerId == null) return;
    // A single foreground timer retries without persisting an auth token or
    // continuously waking a background process. Delay is capped at 15 minutes.
    final index = _retryAttempt < _retryDelays.length
        ? _retryAttempt
        : _retryDelays.length - 1;
    if (_retryAttempt < _retryDelays.length) _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelays[index], () {
      _retryTimer = null;
      if (ref.read(memberSmsIntakeSessionProvider) == session) {
        _sync(newSignal: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) {
      ref.listen<MemberSmsIntakeSession>(memberSmsIntakeSessionProvider, (
        _,
        current,
      ) {
        if (current.ownerId == null) {
          _retryTimer?.cancel();
          _retryTimer = null;
          _retryAttempt = 0;
          _syncRequested = false;
        } else {
          _sync();
        }
      });
    }
    return widget.child;
  }
}
