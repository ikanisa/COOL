import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_motion.dart';

import '../shared/components/admin_data_listing.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_notification_management_api.dart';
import 'cloudflare_admin_session.dart';

part 'cloudflare_admin_notification_management_history.dart';

const _family = 'notification-management';
const _schema = AdminPendingAttemptSchema(
  fields: {'action', 'resource_id', 'expected_decision_revision'},
);
const _maximumDecisionRevision = 9007199254740991;
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class CloudflareAdminNotificationManagementPage extends ConsumerStatefulWidget {
  const CloudflareAdminNotificationManagementPage({super.key});
  @override
  ConsumerState<CloudflareAdminNotificationManagementPage> createState() =>
      _ManagementState();
}

class _ManagementState
    extends ConsumerState<CloudflareAdminNotificationManagementPage>
    with WidgetsBindingObserver {
  late final CloudflareAdminSession _session;
  late final CloudflareAdminNotificationManagementApi _api;
  late final ({int epoch, Object? key}) _fence;
  late final CloudflareAdminUser? _origin;
  late final AdminPendingAttemptStore _references;
  late final ProviderSubscription<AsyncValue<CloudflareAdminUser?>>
  _subscription;
  final _pending = <_Pending>[];
  final _collection = TextEditingController();
  NotificationManagementAccessState? _access;
  NotificationManagementPolicyState? _policy;
  NotificationManagementHistoryPage? _history;
  NotificationManagementHistoryCursor? _historyCursor;
  final _historyBack = <NotificationManagementHistoryCursor?>[];
  _HistoryReadback? _historyReadback;
  NotificationManagementPolicyState? _historyCurrentPolicy;
  bool _historyLoading = false;
  int _historySequence = 0;
  String? _historyError;
  bool _busy = false,
      _foreground = true,
      _departed = false,
      _authorityLost = false;
  bool _accessConfirmed = false,
      _policyConfirmed = false,
      _reopenRequired = false;
  String? _message, _loadError;
  int _generation = 0;
  Timer? _expiry;
  ModalRoute<dynamic>? _route;
  GoRouter? _router;
  Object? _configuration;
  Animation<double>? _secondaryAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _session = ref.read(cloudflareAdminSessionProvider.notifier);
    _origin = _session.user;
    _fence = _session.authorityFence;
    _api = CloudflareAdminNotificationManagementApi(_session);
    _references = AdminPendingAttemptStore(
      storage: _ReferenceStorage(
        ref.read(adminPendingAttemptStorageProvider),
        _session.user,
      ),
    );
    _references.bind(_checkpointActor(_session.user));
    _references.addListener(_storageChanged);
    _subscription = ref.listenManual(cloudflareAdminSessionProvider, (_, next) {
      if (!next.isLoading && !next.hasError) {
        // Principal is also in this namespace; the store itself additionally
        // clears account/email/role/public-session or checkpoint-grant changes.
        final nextUser = next.asData?.value;
        if (_sameCheckpointIdentity(nextUser)) {
          _references.bind(_checkpointActor(nextUser));
        } else {
          _references.bind(null);
          _pending.clear();
        }
      }
      if (_session.authorityFence != _fence || !_api.canManageAccess) {
        _invalidate(authority: true);
      } else {
        _scheduleExpiry();
      }
    });
    _scheduleExpiry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _current) {
        _restore();
        unawaited(_loadAccess());
      }
    });
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final user = _session.user;
    final deadlines = [
      if (user != null) user.expiresAt,
      if (user?.sensitiveVerificationAt != null)
        user!.sensitiveVerificationAt!.add(const Duration(minutes: 5)),
    ]..sort();
    if (deadlines.isNotEmpty) {
      final duration = deadlines.first.difference(DateTime.now());
      _expiry = Timer(
        duration.isNegative ? Duration.zero : duration,
        () => _invalidate(authority: true),
      );
    }
  }

  void _storageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _sameCheckpointIdentity(CloudflareAdminUser? user) =>
      user != null &&
      user.id == _origin?.id &&
      user.email == _origin?.email &&
      user.role == AdminAccountRole.owner &&
      user.role == _origin?.role &&
      user.sessionId == _origin?.sessionId &&
      user.principalId == _origin?.principalId &&
      user.permissions.contains('admin_users.manage');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route == null) {
      _route = route;
      _secondaryAnimation = route?.secondaryAnimation;
      _secondaryAnimation?.addStatusListener(_routeStatus);
    }
    final router = GoRouter.maybeOf(context);
    if (_router == null && router != null) {
      _router = router;
      _configuration = router.routerDelegate.currentConfiguration;
      router.routerDelegate.addListener(_navigationChanged);
    }
  }

  void _routeStatus(AnimationStatus status) {
    // Table filter popups do not depart the underlying Owner review. Actual
    // page transitions and GoRouter configuration changes still fence it.
    if (status == AnimationStatus.forward) {
      _invalidate(departure: true);
    }
  }

  void _navigationChanged() {
    if (_router?.routerDelegate.currentConfiguration != _configuration) {
      _invalidate(departure: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _invalidate();
    } else if (mounted) {
      setState(
        () => _message =
            'Review drafts cleared. Refresh current access before continuing.',
      );
    }
  }

  bool get _current =>
      mounted &&
      _foreground &&
      !_departed &&
      !_authorityLost &&
      !_reopenRequired &&
      _session.authorityFence == _fence &&
      _api.canManageAccess;
  bool get _unresolved => _pending.any((entry) => entry.unresolved);
  bool get _canWrite =>
      _current &&
      !_busy &&
      !_historyLoading &&
      !_unresolved &&
      _references.storageAvailable;
  bool _taskCurrent(int generation) => _current && generation == _generation;

  void _clearDrafts({bool dropOriginal = true}) {
    _access = null;
    _policy = null;
    _accessConfirmed = false;
    _policyConfirmed = false;
    _collection.clear();
    if (dropOriginal) {
      for (final entry in _pending) {
        entry.original = null;
      }
    }
  }

  void _invalidate({bool authority = false, bool departure = false}) {
    if (!mounted) {
      return;
    }
    _generation++;
    _authorityLost |= authority;
    _departed |= departure;
    _clearDrafts();
    _clearHistory();
    _expiry?.cancel();
    if (mounted) {
      setState(
        () => _message =
            'This review left its original authority or foreground. Reopen controls to check current access.',
      );
    }
  }

  void _clearHistory() {
    _historySequence++;
    _history = null;
    _historyCursor = null;
    _historyBack.clear();
    _historyReadback = null;
    _historyCurrentPolicy = null;
    _historyLoading = false;
    _historyError = null;
  }

  Future<void> _loadHistory({
    bool next = false,
    bool previous = false,
    required int expectedSequence,
  }) async {
    if (!_current ||
        !_api.canReadHistory ||
        _busy ||
        _historyLoading ||
        expectedSequence != _historySequence) {
      return;
    }
    NotificationManagementHistoryCursor? after;
    final back = <NotificationManagementHistoryCursor?>[];
    if (next) {
      if (_history?.nextCursor == null) {
        return;
      }
      after = _history!.nextCursor;
      back.addAll([..._historyBack, _historyCursor]);
    } else if (previous) {
      if (_historyBack.isEmpty) {
        return;
      }
      after = _historyBack.last;
      back.addAll(_historyBack.take(_historyBack.length - 1));
    }
    final task = _generation, sequence = ++_historySequence;
    setState(() {
      _historyLoading = true;
      _historyError = null;
      _historyReadback = null;
      _historyCurrentPolicy = null;
      _accessConfirmed = false;
      _policyConfirmed = false;
    });
    try {
      final page = await _api.getHistory(limit: 25, after: after);
      if (_taskCurrent(task) && sequence == _historySequence) {
        setState(() {
          _history = page;
          _historyCursor = after;
          _historyBack
            ..clear()
            ..addAll(back);
        });
      }
    } catch (error) {
      if (_taskCurrent(task) && sequence == _historySequence) {
        setState(() => _historyError = _error(error));
      }
    } finally {
      if (mounted && sequence == _historySequence) {
        setState(() => _historyLoading = false);
      }
    }
  }

  bool _canCheckPending(_Pending pending) => pending.action == 'access'
      ? _api.canReadAccessOperation
      : _api.canReadPolicyOperation;

  bool _canViewHistory(NotificationManagementHistoryItem item) =>
      switch (item.kind) {
        NotificationManagementHistoryKind.access => _api.canReadAccessOperation,
        NotificationManagementHistoryKind.policy => _api.canReadPolicyOperation,
        NotificationManagementHistoryKind.materialization => false,
      };

  Future<void> _viewHistory(
    NotificationManagementHistoryItem item,
    int expectedSequence,
  ) async {
    if (!_current ||
        _busy ||
        _historyLoading ||
        !_canViewHistory(item) ||
        expectedSequence != _historySequence ||
        _history?.items.contains(item) != true) {
      return;
    }
    final task = _generation;
    setState(() {
      _busy = true;
      _historyError = null;
      _historyReadback = null;
      _historyCurrentPolicy = null;
      _accessConfirmed = false;
      _policyConfirmed = false;
    });
    try {
      final _HistoryReadback view;
      switch (item.kind) {
        case NotificationManagementHistoryKind.access:
          final accessStatus = await _api.getAccessOperation(item.requestId);
          view = _HistoryReadback(
            requestId: accessStatus.requestId,
            kind: item.kind,
            receipt: accessStatus.recordedDecision,
            currentAccess: accessStatus.currentAccess,
          );
        case NotificationManagementHistoryKind.policy:
          final policyStatus = await _api.getPolicyOperation(item.requestId);
          view = _HistoryReadback(
            requestId: policyStatus.requestId,
            kind: item.kind,
            receipt: policyStatus.recordedDecision,
          );
        case NotificationManagementHistoryKind.materialization:
          return;
      }
      if (_taskCurrent(task) && expectedSequence == _historySequence) {
        // Discovery is display-only: never resolve a local checkpoint, adopt
        // a current mutation draft, or reconstruct its original RAM command.
        setState(() {
          _historyReadback = view;
          final access = view.currentAccess;
          if (access != null &&
              (_access?.decisionRevision != access.decisionRevision ||
                  _access?.readGranted != access.readGranted ||
                  _access?.manageGranted != access.manageGranted)) {
            // Retire a stale draft without adopting this discovered observation
            // as a command. A new decision requires an explicit current read.
            _access = null;
          }
        });
      }
    } catch (error) {
      if (_taskCurrent(task) && expectedSequence == _historySequence) {
        setState(() => _historyError = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadHistoryPolicy(_HistoryReadback view) async {
    final receipt = view.receipt;
    if (!_current ||
        _busy ||
        _historyLoading ||
        !_api.canManagePolicy ||
        receipt is! NotificationManagementPolicyReceipt ||
        !identical(_historyReadback, view)) {
      return;
    }
    final task = _generation, sequence = _historySequence;
    setState(() {
      _busy = true;
      _historyError = null;
      _historyCurrentPolicy = null;
    });
    try {
      final current = await _api.getPolicy(receipt.collectionId);
      if (_taskCurrent(task) &&
          sequence == _historySequence &&
          identical(_historyReadback, view)) {
        setState(() => _historyCurrentPolicy = current);
      }
    } catch (error) {
      if (_taskCurrent(task) && sequence == _historySequence) {
        setState(() => _historyError = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _restore() {
    try {
      for (final entry in _references.restoreFamily(
        family: _family,
        permission: 'admin_users.manage',
        schema: _schema,
      )) {
        final action = entry.intent['action'],
            resource = entry.intent['resource_id'],
            expectedRevision = entry.intent['expected_decision_revision'];
        if (!_uuid.hasMatch(entry.requestKey) ||
            !const {'access', 'policy'}.contains(action) ||
            resource is! String ||
            !_uuid.hasMatch(resource) ||
            entry.resourceId != '$action:$resource') {
          throw const FormatException('Invalid management recovery reference.');
        }
        final hasRevision = entry.intent.containsKey(
          'expected_decision_revision',
        );
        final revision =
            expectedRevision is int &&
                action == 'access' &&
                expectedRevision >= 0 &&
                expectedRevision < _maximumDecisionRevision
            ? expectedRevision
            : null;
        final pending = _Pending(
          entry.requestKey,
          action as String,
          resource,
          expectedDecisionRevision: revision,
        );
        if (hasRevision && revision == null) {
          // Keep a verified identity visible, but never reinterpret malformed
          // metadata as a legacy confirmation or a known request failure.
          pending.status =
              'The retained access decision revision could not be verified; preserve this original UUID';
          if (!_pending.any((entry) => entry.requestId == pending.requestId)) {
            _pending.add(pending);
          }
          throw const FormatException(
            'Invalid retained access decision revision.',
          );
        }
        if (!_pending.any((pending) => pending.requestId == entry.requestKey)) {
          // Older references may lack the head. Keep their unresolved UUID;
          // current grants or a newer head cannot establish the old outcome.
          _pending.add(pending);
        }
      }
    } catch (_) {
      _authorityLost = true;
      _message =
          'Recovery references could not be verified. Preserve the original UUID for review.';
    }
    setState(() {});
  }

  Future<void> _loadAccess() async {
    if (!_current || _busy || _historyLoading) {
      return;
    }
    final task = _generation;
    setState(() {
      _busy = true;
      _loadError = null;
      _accessConfirmed = false;
    });
    try {
      final access = await _api.getAccess();
      if (_taskCurrent(task)) {
        setState(() => _access = access);
      }
    } catch (error) {
      if (_taskCurrent(task)) {
        setState(() => _loadError = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadPolicy() async {
    if (!_current || !_api.canManagePolicy || _busy || _historyLoading) {
      return;
    }
    final collection = _collection.text.trim().toLowerCase();
    if (!_uuid.hasMatch(collection)) {
      setState(() => _message = 'Enter the exact collection UUID.');
      return;
    }
    final task = _generation;
    setState(() {
      _busy = true;
      _policy = null;
      _policyConfirmed = false;
      _message = null;
    });
    try {
      final policy = await _api.getPolicy(collection);
      if (_taskCurrent(task) &&
          _collection.text.trim().toLowerCase() == collection) {
        setState(() => _policy = policy);
      }
    } catch (error) {
      if (_taskCurrent(task)) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<NotificationManagementReceipt?> _write(
    _Pending pending,
    Future<NotificationManagementReceipt> Function() dispatch,
  ) async {
    if (!_current ||
        _busy ||
        _historyLoading ||
        !_references.storageAvailable) {
      return null;
    }
    final task = _generation;
    var retained = false;
    setState(() {
      _busy = true;
      _message = null;
      if (!_pending.contains(pending)) {
        _pending.add(pending);
      }
    });
    try {
      if (pending.action == 'access' &&
          (pending.expectedDecisionRevision == null ||
              pending.expectedDecisionRevision! < 0 ||
              pending.expectedDecisionRevision! >= _maximumDecisionRevision)) {
        throw const AdminAccountException(
          'The original access decision revision could not be retained. No request was submitted.',
        );
      }
      _references.retain(
        family: _family,
        resourceId: pending.storageId,
        requestKey: pending.requestId,
        permission: 'admin_users.manage',
        intent: {
          'action': pending.action,
          'resource_id': pending.resourceId,
          'expected_decision_revision': ?pending.expectedDecisionRevision,
        },
        schema: _schema,
      );
      retained = true;
      if (!_references.storageAvailable) {
        throw const AdminAccountException(
          'Recovery storage is unavailable. No request was submitted.',
        );
      }
      if (!_taskCurrent(task)) {
        return null;
      }
      final receipt = await dispatch();
      if (!_taskCurrent(task)) {
        return null;
      }
      _record(pending, receipt);
      return receipt;
    } catch (error) {
      if (!_taskCurrent(task)) {
        return null;
      }
      if (pending.original?.dispatched != true) {
        pending.unresolved = false;
        pending.status = 'Not submitted';
        pending.original = null;
        if (retained) {
          _references.clear(family: _family, resourceId: pending.storageId);
        } else {
          _restore();
        }
      } else {
        pending.status = 'Outcome unknown: keep this exact original UUID';
        _clearDrafts(dropOriginal: false);
      }
      setState(() => _message = _error(error));
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _record(_Pending pending, NotificationManagementReceipt receipt) {
    final resource = receipt is NotificationManagementAccessReceipt
        ? receipt.principalId
        : (receipt as NotificationManagementPolicyReceipt).collectionId;
    if (receipt.requestId != pending.requestId ||
        receipt.action != pending.action ||
        resource != pending.resourceId ||
        receipt is NotificationManagementAccessReceipt &&
            pending.expectedDecisionRevision != null &&
            receipt.decisionRevision != pending.expectedDecisionRevision! + 1) {
      throw const FormatException(
        'The receipt does not match the retained original reference.',
      );
    }
    pending.unresolved = false;
    pending.original = null;
    pending.status =
        'Recorded historical decision; current state requires a separate read';
    pending.facts = _receiptFacts(receipt);
    _references.clear(family: _family, resourceId: pending.storageId);
    setState(() {});
  }

  void _confirmAccess(bool? value) {
    if (_canWrite) {
      setState(() => _accessConfirmed = value == true);
    }
  }

  Future<void> _setAccess(bool enabled) async {
    final expected = _access;
    if (!_canWrite || expected == null || enabled && !_accessConfirmed) {
      return;
    }
    try {
      final operation = _api.prepareAccess(
        expected: expected,
        enabled: enabled,
        ownerConfirmation: enabled && _accessConfirmed,
      );
      final pending = _Pending(
        operation.requestId,
        operation.action,
        operation.resourceId,
        original: operation,
        expectedDecisionRevision: operation.expectedDecisionRevision,
      );
      final receipt = await _write(pending, () => _api.setAccess(operation));
      if (receipt != null && _current) {
        await _afterAccessDecision();
      }
    } catch (error) {
      if (_current) {
        setState(() => _message = _error(error));
      }
    }
  }

  Future<void> _afterAccessDecision() async {
    final task = _generation;
    setState(() {
      _busy = true;
      _accessConfirmed = false;
    });
    try {
      // A recorded/replayed enable decision is not actual current grants.
      final current = await _api.getAccess();
      if (_taskCurrent(task)) {
        setState(() => _access = current);
      }
    } catch (error) {
      if (_taskCurrent(task)) {
        setState(
          () => _message =
              'The decision was recorded. Current access could not be verified: ${_error(error)}',
        );
      }
    }
    if (_taskCurrent(task)) {
      // Permission changes intentionally advance the session fence. This
      // controller must stop rather than adopting authority from a later one.
      _reopenRequired = true;
      await _session.refresh();
      if (mounted) {
        _invalidate(authority: true);
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _disablePolicy() async {
    final expected = _policy;
    if (!_canWrite ||
        !_api.canManagePolicy ||
        expected == null ||
        !_policyConfirmed ||
        !expected.enabled) {
      return;
    }
    try {
      final operation = _api.preparePolicy(
        expected: expected,
        enabled: false,
        ownerConfirmation: false,
      );
      final pending = _Pending(
        operation.requestId,
        operation.action,
        operation.resourceId,
        original: operation,
      );
      final receipt = await _write(pending, () => _api.setPolicy(operation));
      if (receipt != null && _current) {
        await _loadPolicy();
      }
    } catch (error) {
      if (_current) {
        setState(() => _message = _error(error));
      }
    }
  }

  Future<void> _check(_Pending pending) async {
    if (!_current || !_canCheckPending(pending) || _busy || _historyLoading) {
      return;
    }
    final task = _generation;
    var refreshSession = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (pending.action == 'access') {
        final result = await _api.getAccessOperation(
          pending.requestId,
          originalOperation: pending.original,
        );
        if (_taskCurrent(task)) {
          if (result.recordedDecision case final receipt?) {
            _record(pending, receipt);
            final permissions = _session.user!.permissions;
            refreshSession =
                result.currentAccess.readGranted !=
                    permissions.contains('assisted_sms.read') ||
                result.currentAccess.manageGranted !=
                    permissions.contains('assisted_sms.manage');
          } else {
            pending.status =
                'No recorded result observed; it may still be in flight. Original operation remains unresolved';
          }
          setState(() {
            // Only the independently current observation can supply this state.
            // The historical receipt and expected head never supply grants.
            _access = result.currentAccess;
            _accessConfirmed = false;
          });
        }
      } else {
        final result = await _api.getPolicyOperation(
          pending.requestId,
          originalOperation: pending.original,
        );
        if (_taskCurrent(task)) {
          if (result.recordedDecision case final receipt?) {
            _record(pending, receipt);
          } else {
            setState(
              () => pending.status =
                  'No recorded result observed; it may still be in flight. Original operation remains unresolved',
            );
          }
        }
      }
    } catch (error) {
      if (_taskCurrent(task)) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (refreshSession && _current) {
      await _afterAccessDecision();
    }
  }

  Future<void> _replay(_Pending pending) async {
    final original = pending.original;
    if (!_current ||
        _busy ||
        _historyLoading ||
        original == null ||
        !pending.unresolved) {
      return;
    }
    final receipt = await _write(
      pending,
      () => pending.action == 'access'
          ? _api.replayAccess(original)
          : _api.replayPolicy(original),
    );
    if (receipt is NotificationManagementAccessReceipt && _current) {
      await _afterAccessDecision();
    } else if (receipt is NotificationManagementPolicyReceipt && _current) {
      await _loadPolicy();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cloudflareAdminSessionProvider);
    final current = _current;
    return Material(
      type: MaterialType.transparency,
      child: AdminPage(
        title: 'Assisted SMS controls',
        trailing: IconButton(
          tooltip: 'Refresh current assisted SMS access',
          onPressed: current && !_busy && !_historyLoading ? _loadAccess : null,
          icon: const Icon(Icons.refresh, size: 26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!current)
              _Message(
                'Reopen controls with the actual Owner account, permission to manage Team access and ${_session.user?.usesEmailVerification == true ? 'recent email verification' : 'fresh authenticator verification'}. Assisted SMS grants are not required to check self-access.',
              ),
            if (!current &&
                _session.user?.usesEmailVerification == true &&
                _session.user?.role == AdminAccountRole.owner &&
                _session.user?.email == 'info@ikanisa.com' &&
                _session.user?.permissions.contains('admin_users.manage') ==
                    true)
              TextButton.icon(
                onPressed: () => context.go(
                  Uri(
                    path: '/admin/security/verify-email',
                    queryParameters: {
                      'returnTo': GoRouterState.of(context).uri.toString(),
                    },
                  ).toString(),
                ),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Verify email'),
              ),
            if (!current)
              _ContextDetails(
                key: const Key('notification-management-access-requirements'),
                title: 'Access requirements',
                semanticLabel: 'Assisted SMS access requirements',
                fields: [
                  ('Account role', 'Owner'),
                  ('Existing Team access permission', 'admin_users.manage'),
                  (
                    'Verification',
                    _session.user?.usesEmailVerification == true
                        ? 'Recent email verification'
                        : 'Fresh AAL2 authenticator verification',
                  ),
                ],
              ),
            if (_message != null) _Message(_message!),
            if (_pending.isNotEmpty) ...[
              _heading(context, 'Original management operations'),
              for (final entry in _pending.where((entry) => entry.unresolved))
                AdminRecordFactsTable(
                  semanticLabel:
                      'Unresolved original request ${entry.requestId}',
                  fields: [
                    ('Original UUID', entry.requestId),
                    (
                      'Action',
                      entry.action == 'access'
                          ? 'Self-access'
                          : 'Collection policy',
                    ),
                    ('Status', entry.status),
                    if (entry.action == 'access')
                      (
                        'Expected access decision revision',
                        entry.expectedDecisionRevision?.toString() ??
                            'Not retained',
                      ),
                  ],
                ),
              AdminDataTable(
                tableLabel: 'Original assisted SMS management operations',
                rows: [
                  for (final entry in _pending)
                    _row(entry.requestId, {
                      'request_id': entry.requestId,
                      'action': entry.action == 'access'
                          ? 'Self-access'
                          : 'Collection policy',
                      'resource_id': entry.resourceId,
                      'status': entry.status,
                    }),
                ],
                columns: [
                  AdminTableColumn(
                    label: 'Receipt lookup',
                    value: (_) => 'Check recorded operation',
                    cellBuilder: (row) {
                      final entry = _pending.firstWhere(
                        (entry) => entry.requestId == row.id,
                      );
                      return OutlinedButton.icon(
                        onPressed:
                            current &&
                                !_busy &&
                                !_historyLoading &&
                                _canCheckPending(entry)
                            ? () => _check(entry)
                            : null,
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Check recorded operation'),
                      );
                    },
                  ),
                  AdminTableColumn(
                    label: 'Exact original request',
                    value: (_) => 'Check or resume exact original request',
                    cellBuilder: (row) {
                      final entry = _pending.firstWhere(
                        (entry) => entry.requestId == row.id,
                      );
                      if (!entry.unresolved || entry.original == null) {
                        return const Text('No live original command');
                      }
                      return OutlinedButton.icon(
                        onPressed:
                            current &&
                                !_busy &&
                                !_historyLoading &&
                                _references.storageAvailable
                            ? () => _replay(entry)
                            : null,
                        icon: const Icon(Icons.history),
                        label: const Text(
                          'Check or resume exact original request',
                        ),
                      );
                    },
                  ),
                  _column('request_id', 'Original UUID'),
                  _column('action', 'Action'),
                  _column('status', 'Status'),
                ],
              ),
              for (final entry in _pending) ...[
                if (entry.facts.isNotEmpty)
                  AdminRecordFactsTable(
                    semanticLabel:
                        'Recorded historical decision ${entry.requestId}',
                    fields: [
                      ('Original UUID', entry.requestId),
                      ..._primaryDecisionFacts(entry.facts),
                    ],
                  ),
                _ContextDetails(
                  key: ValueKey(
                    'management-original-details:${entry.requestId}',
                  ),
                  title: 'Original request details',
                  semanticLabel: 'Original request details ${entry.requestId}',
                  fields: [
                    ('Original UUID', entry.requestId),
                    ('Resource ID', entry.resourceId),
                    ..._secondaryDecisionFacts(entry.facts),
                  ],
                ),
              ],
              if (_unresolved)
                const _Message(
                  'An original request is unresolved. Current access or policy reads do not prove its recorded outcome. Another UUID cannot be submitted. Reopened references cannot reconstruct the original decision; preserve the UUID for receipt review.',
                ),
            ],
            if (current) ...[
              ..._currentAccessWidgets(this, context),
              ..._historyWidgets(this, context),
              _heading(context, 'Collection policy'),
              if (!_api.canManagePolicy)
                const _Message(
                  'Permission to review and record assisted SMS operations is required to read or change a collection policy.',
                ),
              TextField(
                controller: _collection,
                enabled: !_busy && !_historyLoading && _api.canManagePolicy,
                decoration: const InputDecoration(labelText: 'Collection UUID'),
                onChanged: (_) => setState(() {
                  _policy = null;
                  _policyConfirmed = false;
                }),
                onSubmitted: (_) => _loadPolicy(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: !_busy && !_historyLoading && _api.canManagePolicy
                      ? _loadPolicy
                      : null,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check current collection policy'),
                ),
              ),
              if (_policy case final policy?) ...[
                AdminRecordFactsTable(
                  semanticLabel: 'Actual current collection receipt SMS policy',
                  fields: [
                    ('Collection ID', policy.collectionId),
                    ('Configured', policy.configured ? 'Yes' : 'No'),
                    ('Enabled', policy.enabled ? 'Yes' : 'No'),
                    ('Current revision', '${policy.revision}'),
                    (
                      'Collection active',
                      policy.collectionActive ? 'Yes' : 'No',
                    ),
                    (
                      'Recorded at',
                      policy.recordedAt == null
                          ? 'Not recorded'
                          : adminKigaliDateTime(policy.recordedAt),
                    ),
                  ],
                ),
                _ContextDetails(
                  key: const Key('notification-management-policy-details'),
                  title: 'Collection policy details',
                  semanticLabel: 'Collection policy technical details',
                  fields: [
                    ('Template', policy.templateKey),
                    (
                      'Recorded Owner decision SHA-256',
                      policy.recordedOwnerDecisionSha256 ?? 'Not recorded',
                    ),
                    ('Required operations permission', 'assisted_sms.manage'),
                  ],
                ),
                if (policy.enabled)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _policyConfirmed,
                    onChanged: _canWrite
                        ? (value) =>
                              setState(() => _policyConfirmed = value == true)
                        : null,
                    title: const Text(
                      'I confirm disabling receipt SMS for this exact collection and revision',
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const FilledButton(
                      onPressed: null,
                      child: Text('Enable receipt SMS policy'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _canWrite && policy.enabled && _policyConfirmed
                          ? _disablePolicy
                          : null,
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Disable current collection policy'),
                    ),
                  ],
                ),
              ],
              _heading(context, 'Prepare bounded jobs'),
              const _Message(
                'Job preparation is unavailable while the recoverable batch contract is being qualified. No batch is queued or automatically retried.',
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: null,
                  child: Text('Prepare bounded receipt SMS jobs'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _clearDrafts();
    _clearHistory();
    _expiry?.cancel();
    _subscription.close();
    _references.removeListener(_storageChanged);
    _references.dispose();
    _router?.routerDelegate.removeListener(_navigationChanged);
    _secondaryAnimation?.removeStatusListener(_routeStatus);
    WidgetsBinding.instance.removeObserver(this);
    _collection.dispose();
    super.dispose();
  }
}
