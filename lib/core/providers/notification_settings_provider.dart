import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import 'engagement_providers.dart';
import '../services/fcm_service.dart';

class NotificationSettingsState {
  const NotificationSettingsState({
    this.status = const FcmStatus(),
    this.isLoading = false,
    this.error,
  });

  static const _sentinel = Object();

  final FcmStatus status;
  final bool isLoading;
  final String? error;

  NotificationSettingsState copyWith({
    FcmStatus? status,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return NotificationSettingsState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<
      NotificationSettingsNotifier,
      NotificationSettingsState
    >((ref) {
      return NotificationSettingsNotifier(
        ref: ref,
        service: ref.watch(fcmServiceProvider),
      );
    });

class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsNotifier({required Ref ref, required FcmService service})
    : _ref = ref,
      _service = service,
      super(NotificationSettingsState(status: service.currentStatus)) {
    Future<void>.microtask(load);
  }

  final Ref _ref;
  final FcmService _service;

  Future<void> load() async {
    final status = await _service.status();
    state = state.copyWith(status: status, isLoading: false, error: null);
  }

  Future<void> refresh() => load();

  Future<void> setEnabled(bool enabled) async {
    final authState = _ref.read(authProvider);
    final userId = authState.user?.id ?? authState.session?.user.id;

    if (enabled && (userId == null || userId.isEmpty)) {
      state = state.copyWith(
        isLoading: false,
        error: 'A signed-in session is required to enable notifications.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    final status = enabled
        ? await _service.enable(userId: userId!)
        : await _service.disable(userId: userId);

    state = state.copyWith(
      status: status,
      isLoading: false,
      error: status.lastError,
    );
  }

  Future<void> initializeForAuthState(AuthState authState) async {
    final userId = authState.user?.id ?? authState.session?.user.id;
    if (userId == null || userId.isEmpty) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    var status = await _service.initialize(userId: userId);
    status = await _service.syncTopics();
    state = state.copyWith(
      status: status,
      isLoading: false,
      error: status.lastError,
    );
  }

  Future<void> syncTopicsForAuthState(AuthState authState) async {
    if (authState.session == null) {
      return;
    }

    final status = await _service.syncTopics();
    state = state.copyWith(
      status: status,
      isLoading: false,
      error: status.lastError,
    );
  }

  Future<void> clearSession({required String userId}) async {
    state = state.copyWith(isLoading: true, error: null);
    final status = await _service.clearSession(userId: userId);
    state = state.copyWith(
      status: status,
      isLoading: false,
      error: status.lastError,
    );
  }
}
