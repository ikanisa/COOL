import 'dart:async';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/mobility/services/trip_sync_service.dart';

class TripSyncCoordinator {
  TripSyncCoordinator({
    required AuthState Function() readAuthState,
    required TripSyncService tripSyncService,
    this.pollInterval = const Duration(minutes: 1),
  }) : _readAuthState = readAuthState,
       _tripSyncService = tripSyncService;

  final AuthState Function() _readAuthState;
  final TripSyncService _tripSyncService;
  final Duration pollInterval;

  Timer? _pollTimer;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    scheduleSync(source: 'session_restore');
    _pollTimer = Timer.periodic(
      pollInterval,
      (_) => scheduleSync(source: 'periodic_poll'),
    );
  }

  void onAppResumed() {
    scheduleSync(source: 'app_resumed');
  }

  void scheduleSync({required String source}) {
    final session = _readAuthState().session;
    if (session == null) {
      return;
    }

    unawaited(
      _tripSyncService.syncPendingTrips(
        userId: session.user.id,
        source: source,
      ),
    );
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _started = false;
  }
}
