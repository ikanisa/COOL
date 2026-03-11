import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/momo_sms_history_store.dart';
import '../../../core/services/momo_sms_listener.dart';
import '../../../core/services/momo_sms_parser.dart';
import '../../../core/services/momo_sms_permission_service.dart';
import '../../../core/services/momo_sms_policy_service.dart';
import '../../groups/providers/groups_provider.dart';
import '../../mobility/providers/driver_provider.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../repositories/momo_sms_ingestion_repository.dart';
import '../repositories/momo_payment_sync_repository.dart';

/// Single instance of [MomoSmsListener] shared across the app.
final momoSmsListenerProvider = Provider<MomoSmsListener>((ref) {
  final listener = MomoSmsListener(
    permissionService: ref.watch(momoSmsPermissionServiceProvider),
  );
  ref.onDispose(listener.dispose);
  return listener;
});

final momoSmsPermissionServiceProvider = Provider<MomoSmsPermissionService>((
  ref,
) {
  return MomoSmsPermissionService.instance;
});

final momoSmsPolicyServiceProvider = Provider<MomoSmsPolicyService>((ref) {
  return MomoSmsPolicyService.instance;
});

final momoSmsHistoryStoreProvider = Provider<MomoSmsHistoryStore>((ref) {
  return MomoSmsHistoryStore.instance;
});

/// Live stream of parsed MoMo transactions detected from incoming SMS.
final momoTransactionStreamProvider = StreamProvider<MomoTransaction>((ref) {
  final listener = ref.watch(momoSmsListenerProvider);
  return listener.transactions;
});

/// Scans the SMS inbox for MoMo transactions received in the last 30 min.
final missedMomoTransactionsProvider = FutureProvider<List<MomoTransaction>>((
  ref,
) {
  final listener = ref.watch(momoSmsListenerProvider);
  return listener.checkMissedTransactions();
});

final momoSmsHistoryProvider = FutureProvider<List<MomoSmsHistoryEntry>>((ref) {
  final store = ref.watch(momoSmsHistoryStoreProvider);
  return store.recent();
});

final momoPaymentSyncRepositoryProvider = Provider<MomoPaymentSyncRepository>((
  ref,
) {
  return MomoPaymentSyncRepository();
});

final momoSmsIngestionRepositoryProvider = Provider<MomoSmsIngestionRepository>(
  (ref) {
    return MomoSmsIngestionRepository();
  },
);

final momoPaymentSyncProvider =
    StateNotifierProvider<MomoPaymentSyncNotifier, MomoPaymentSyncState>((ref) {
      final listener = ref.watch(momoSmsListenerProvider);
      final repository = ref.watch(momoPaymentSyncRepositoryProvider);
      final ingestionRepository = ref.watch(momoSmsIngestionRepositoryProvider);
      final permissionService = ref.watch(momoSmsPermissionServiceProvider);
      final policyService = ref.watch(momoSmsPolicyServiceProvider);
      final historyStore = ref.watch(momoSmsHistoryStoreProvider);
      return MomoPaymentSyncNotifier(
        ref: ref,
        listener: listener,
        repository: repository,
        ingestionRepository: ingestionRepository,
        permissionService: permissionService,
        policyService: policyService,
        historyStore: historyStore,
      );
    });

enum MomoSmsPromptType {
  none,
  consentRequired,
  permissionDenied,
  permissionPermanentlyDenied,
}

class MomoPaymentSyncState {
  const MomoPaymentSyncState({
    this.isListening = false,
    this.isSyncing = false,
    this.isSupportedPlatform = true,
    this.isPolicyEnabled = true,
    this.hasUserConsent = false,
    this.permissionStatus = MomoSmsPermissionStatus.unsupported,
    this.pendingPrompt = MomoSmsPromptType.none,
    this.recoveredTransactions = 0,
    this.lastReference,
    this.error,
  });

  static const _sentinel = Object();

  final bool isListening;
  final bool isSyncing;
  final bool isSupportedPlatform;
  final bool isPolicyEnabled;
  final bool hasUserConsent;
  final MomoSmsPermissionStatus permissionStatus;
  final MomoSmsPromptType pendingPrompt;
  final int recoveredTransactions;
  final String? lastReference;
  final String? error;

  MomoPaymentSyncState copyWith({
    bool? isListening,
    bool? isSyncing,
    bool? isSupportedPlatform,
    bool? isPolicyEnabled,
    bool? hasUserConsent,
    MomoSmsPermissionStatus? permissionStatus,
    MomoSmsPromptType? pendingPrompt,
    int? recoveredTransactions,
    Object? lastReference = _sentinel,
    Object? error = _sentinel,
  }) {
    return MomoPaymentSyncState(
      isListening: isListening ?? this.isListening,
      isSyncing: isSyncing ?? this.isSyncing,
      isSupportedPlatform: isSupportedPlatform ?? this.isSupportedPlatform,
      isPolicyEnabled: isPolicyEnabled ?? this.isPolicyEnabled,
      hasUserConsent: hasUserConsent ?? this.hasUserConsent,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      pendingPrompt: pendingPrompt ?? this.pendingPrompt,
      recoveredTransactions:
          recoveredTransactions ?? this.recoveredTransactions,
      lastReference: lastReference == _sentinel
          ? this.lastReference
          : lastReference as String?,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

class MomoPaymentSyncNotifier extends StateNotifier<MomoPaymentSyncState> {
  MomoPaymentSyncNotifier({
    required Ref ref,
    required MomoSmsListener listener,
    required MomoPaymentSyncRepository repository,
    required MomoSmsIngestionRepository ingestionRepository,
    required MomoSmsPermissionService permissionService,
    required MomoSmsPolicyService policyService,
    required MomoSmsHistoryStore historyStore,
  }) : _ref = ref,
       _listener = listener,
       _repository = repository,
       _ingestionRepository = ingestionRepository,
       _permissionService = permissionService,
       _policyService = policyService,
       _historyStore = historyStore,
       super(const MomoPaymentSyncState());

  final Ref _ref;
  final MomoSmsListener _listener;
  final MomoPaymentSyncRepository _repository;
  final MomoSmsIngestionRepository _ingestionRepository;
  final MomoSmsPermissionService _permissionService;
  final MomoSmsPolicyService _policyService;
  final MomoSmsHistoryStore _historyStore;

  StreamSubscription<MomoTransaction>? _subscription;
  bool _initialized = false;

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) {
      return;
    }

    final currentUserId = _repository.currentUserId;
    if (currentUserId == null) {
      return;
    }

    if (!_policyService.isSupportedPlatform) {
      _initialized = true;
      state = state.copyWith(
        isListening: false,
        isSyncing: false,
        isSupportedPlatform: false,
        isPolicyEnabled: false,
        hasUserConsent: false,
        permissionStatus: MomoSmsPermissionStatus.unsupported,
        pendingPrompt: MomoSmsPromptType.none,
        recoveredTransactions: 0,
        error: null,
      );
      return;
    }

    if (!_policyService.isFeatureAvailable) {
      _initialized = true;
      final permissionStatus = await _permissionService.getStatus();
      state = state.copyWith(
        isListening: false,
        isSyncing: false,
        isSupportedPlatform: true,
        isPolicyEnabled: false,
        hasUserConsent: false,
        permissionStatus: permissionStatus,
        pendingPrompt: MomoSmsPromptType.none,
        recoveredTransactions: 0,
        error: null,
      );
      return;
    }

    final hasUserConsent = await _policyService.hasUserConsent();
    if (!hasUserConsent) {
      state = state.copyWith(
        isListening: false,
        isSyncing: false,
        isSupportedPlatform: true,
        isPolicyEnabled: true,
        hasUserConsent: false,
        permissionStatus: await _permissionService.getStatus(),
        pendingPrompt: MomoSmsPromptType.consentRequired,
        recoveredTransactions: 0,
        error: null,
      );
      return;
    }

    state = state.copyWith(
      isSyncing: true,
      isSupportedPlatform: true,
      isPolicyEnabled: true,
      hasUserConsent: true,
      pendingPrompt: MomoSmsPromptType.none,
      error: null,
    );

    final started = await _listener.start();
    final permissionStatus = await _permissionService.getStatus();
    if (!started) {
      state = state.copyWith(
        isListening: false,
        isSyncing: false,
        permissionStatus: permissionStatus,
        pendingPrompt: _promptFor(permissionStatus),
        error: _errorFor(permissionStatus),
      );
      return;
    }

    _subscription ??= _listener.transactions.listen((transaction) {
      unawaited(_processTransaction(transaction));
    });

    final missedTransactions = await _listener.checkMissedTransactions();
    for (final transaction in missedTransactions) {
      await _processTransaction(transaction);
    }

    _initialized = true;
    state = state.copyWith(
      isListening: true,
      isSyncing: false,
      permissionStatus: permissionStatus,
      pendingPrompt: MomoSmsPromptType.none,
      recoveredTransactions: missedTransactions.length,
      error: null,
    );
  }

  Future<void> enableSmsSync() async {
    await _policyService.setUserConsent(true);
    state = state.copyWith(
      hasUserConsent: true,
      pendingPrompt: MomoSmsPromptType.none,
      error: null,
    );
    await initialize(force: true);
  }

  Future<void> retrySmsSetup() async {
    state = state.copyWith(pendingPrompt: MomoSmsPromptType.none, error: null);
    await initialize(force: true);
  }

  Future<void> openSmsSettings() async {
    await _permissionService.openSettings();
    state = state.copyWith(pendingPrompt: MomoSmsPromptType.none);
  }

  void dismissPrompt() {
    state = state.copyWith(pendingPrompt: MomoSmsPromptType.none);
  }

  Future<void> _processTransaction(MomoTransaction transaction) async {
    final historyEntry = await _historyStore.recordDetected(transaction);
    _ref.invalidate(momoSmsHistoryProvider);
    if (historyEntry.status == MomoSmsHistoryStatus.confirmed ||
        historyEntry.status == MomoSmsHistoryStatus.unmatched) {
      return;
    }

    final ingestionResult = await _ingestionRepository.ingestTransaction(
      transaction,
    );
    if (ingestionResult == null) {
      await _historyStore.markUnmatched(transaction);
      _ref.invalidate(momoSmsHistoryProvider);
      return;
    }

    await _historyStore.markProcessing(
      transaction,
      rawSmsId: ingestionResult.rawSmsId,
    );
    _ref.invalidate(momoSmsHistoryProvider);

    final result = await _repository.resolveServerReconciliation(
      rawSmsId: ingestionResult.rawSmsId,
    );
    if (result == null) {
      await _historyStore.markUnmatched(transaction);
      _ref.invalidate(momoSmsHistoryProvider);
      return;
    }

    switch (result.status) {
      case MomoPaymentSyncStatus.processing:
        await _historyStore.markProcessing(
          transaction,
          rawSmsId: ingestionResult.rawSmsId,
          matchedReference: result.reference,
        );
        _ref.invalidate(momoSmsHistoryProvider);
        return;
      case MomoPaymentSyncStatus.reviewRequired:
        await _historyStore.markReviewRequired(
          transaction,
          rawSmsId: ingestionResult.rawSmsId,
          matchedReference: result.reference,
        );
        _ref.invalidate(momoSmsHistoryProvider);
        return;
      case MomoPaymentSyncStatus.unmatched:
        await _historyStore.markUnmatched(transaction);
        _ref.invalidate(momoSmsHistoryProvider);
        return;
      case MomoPaymentSyncStatus.confirmed:
        await _historyStore.markConfirmed(
          transaction,
          rawSmsId: ingestionResult.rawSmsId,
          matchedReference: result.reference,
        );
        _ref.invalidate(momoSmsHistoryProvider);
        state = state.copyWith(lastReference: result.reference, error: null);

        switch (result.matchType) {
          case MomoPaymentMatchType.groupContribution:
            unawaited(_ref.read(groupsProvider.notifier).loadMyGroups());
            if (result.groupId case final groupId?) {
              unawaited(
                _ref.read(groupsProvider.notifier).loadGroupDetail(groupId),
              );
            }
            break;
          case MomoPaymentMatchType.driverSubscription:
            unawaited(
              _ref.read(driverProvider.notifier).checkSubscriptionStatus(),
            );
            break;
          case MomoPaymentMatchType.rayonTicket:
          case MomoPaymentMatchType.rayonShopOrder:
          case MomoPaymentMatchType.rayonInitiativeContribution:
            unawaited(_ref.read(rayonSportsProvider.notifier).load());
            break;
          case MomoPaymentMatchType.pendingTransaction:
          case MomoPaymentMatchType.unknown:
            break;
        }
        return;
    }
  }

  MomoSmsPromptType _promptFor(MomoSmsPermissionStatus status) {
    switch (status) {
      case MomoSmsPermissionStatus.supportedPermanentlyDenied:
        return MomoSmsPromptType.permissionPermanentlyDenied;
      case MomoSmsPermissionStatus.supportedDenied:
        return MomoSmsPromptType.permissionDenied;
      case MomoSmsPermissionStatus.supportedGranted:
      case MomoSmsPermissionStatus.unsupported:
        return MomoSmsPromptType.none;
    }
  }

  String? _errorFor(MomoSmsPermissionStatus status) {
    switch (status) {
      case MomoSmsPermissionStatus.supportedDenied:
        return 'SMS permission is required for MOMO confirmation detection.';
      case MomoSmsPermissionStatus.supportedPermanentlyDenied:
        return 'SMS permission is blocked. Open Android settings to enable MOMO confirmation detection.';
      case MomoSmsPermissionStatus.supportedGranted:
      case MomoSmsPermissionStatus.unsupported:
        return null;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
