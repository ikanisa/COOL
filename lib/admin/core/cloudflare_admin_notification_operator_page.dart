import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../shared/components/admin_data_listing.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_models.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_notification_operator_api.dart';
import 'cloudflare_admin_session.dart';

const _family = 'notification-operator';
const _schema = AdminPendingAttemptSchema(fields: {'action', 'resource_id'});
const _actions = {
  'claim',
  'confirm',
  'record_send_start',
  'release_claim',
  'record_outcome',
};
final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);

/// A native integration must take the payload immediately before its one
/// dispatch, accept a null payload as cancellation, and never retry. No native
/// implementation, composer, clipboard or provider is supplied by this page.
abstract interface class NotificationOperatorAssistedSmsAdapter {
  Future<NotificationOperatorAdapterObservation> sendOnce(
    NotificationOperatorNativeSendContext context,
  );
}

class NotificationOperatorAdapterObservation {
  const NotificationOperatorAdapterObservation({
    required this.observation,
    required this.evidenceReferenceSha256,
  });
  final NotificationOperatorObservation observation;
  final String evidenceReferenceSha256;
}

class NotificationOperatorNativePayload {
  const NotificationOperatorNativePayload._(
    this.attemptId,
    this.destinationE164,
    this.messageBody,
  );
  final String attemptId, destinationE164, messageBody;
}

/// Ephemeral, single-take handoff. Lifecycle invalidation erases the payload
/// even if an injected adapter has retained this context while awaiting work.
class NotificationOperatorNativeSendContext {
  NotificationOperatorNativeSendContext._(
    this._payload,
    this._permit,
    this._current,
  );
  NotificationOperatorNativePayload? _payload;
  NotificationOperatorSendPermit? _permit;
  final bool Function() _current;
  NotificationOperatorNativePayload? takeForImmediateDispatch() {
    final payload = _payload, permit = _permit;
    _payload = null;
    _permit = null;
    if (!_current() || permit?.consume() != true) return null;
    return payload;
  }

  void _invalidate() {
    _payload = null;
    // Burn a still-unconsumed permit as well as removing this handoff's
    // reference, so a delayed native task cannot revive it after departure.
    _permit?.consume();
    _permit = null;
  }
}

class CloudflareAdminNotificationOperatorPage extends ConsumerStatefulWidget {
  const CloudflareAdminNotificationOperatorPage({
    this.assistedSmsAdapter,
    super.key,
  });
  final NotificationOperatorAssistedSmsAdapter? assistedSmsAdapter;
  @override
  ConsumerState<CloudflareAdminNotificationOperatorPage> createState() =>
      _OperatorPageState();
}

class _Reference {
  _Reference(this.requestId, this.action, this.resourceId, {this.original});
  final String requestId, action, resourceId;
  NotificationOperatorOperation? original;
  bool unresolved = true;
  String status = 'Check the original operation';
  List<(String, String)> receipt = const [];
}

class _OperatorPageState
    extends ConsumerState<CloudflareAdminNotificationOperatorPage>
    with WidgetsBindingObserver {
  late final CloudflareAdminSession _session;
  late final CloudflareAdminNotificationOperatorApi _api;
  late final ({int epoch, Object? key}) _authority;
  late final ProviderSubscription<AsyncValue<CloudflareAdminUser?>>
  _subscription;
  final _references = <_Reference>[];
  final _previous = <NotificationOperatorCursor?>[];
  final _lookup = TextEditingController();
  final _evidence = TextEditingController();
  final _workerId = 'collect-admin-${const Uuid().v4()}';
  NotificationOperatorCursor? _cursor;
  NotificationOperatorPendingPage? _page;
  NotificationOperatorClaim? _claim;
  NotificationOperatorContent? _content;
  NotificationOperatorConfirmation? _confirmation;
  NotificationOperatorNativeSendContext? _nativeContext;
  NotificationOperatorObservation _observation =
      NotificationOperatorObservation.uncertain;
  String? _attemptId, _message, _loadError;
  bool _loading = false, _busy = false, _checked = false, _foreground = true;
  bool _departed = false, _authorityLost = false, _restored = false;
  int _generation = 0, _loadGeneration = 0;
  Timer? _deadline;
  GoRouter? _router;
  Object? _configuration;
  ModalRoute<dynamic>? _route;
  Animation<double>? _secondaryAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _session = ref.read(cloudflareAdminSessionProvider.notifier);
    _authority = _session.authorityFence;
    _api = CloudflareAdminNotificationOperatorApi(_session);
    _subscription = ref.listenManual(cloudflareAdminSessionProvider, (_, _) {
      if (_session.authorityFence != _authority || !_api.canRead) {
        _invalidate(authority: true);
      } else {
        // Renewed proof changes freshness, not the original task's authority.
        // Existing claim/confirmation deadlines still bound the same task.
        _scheduleDeadline();
      }
    });
    _scheduleDeadline();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restore();
      unawaited(_load());
    });
  }

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

  // Popup routes (including this page's outcome dropdown) temporarily make
  // isCurrent false without leaving the operator task. Page transitions and
  // the router configuration listener handle actual navigation away.
  void _routeStatus(AnimationStatus status) {
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
            'Sensitive review cleared. Refresh pending jobs to continue.',
      );
    }
  }

  bool get _current =>
      mounted &&
      _foreground &&
      !_departed &&
      !_authorityLost &&
      _session.authorityFence == _authority &&
      _api.canRead;
  bool get _unresolved => _references.any((reference) => reference.unresolved);
  bool get _canMutate =>
      _current &&
      _api.canManage &&
      !_busy &&
      !_unresolved &&
      ref.read(adminPendingAttemptStoreProvider).storageAvailable;
  bool _taskCurrent(int generation) => _current && generation == _generation;

  void _selectAttempt(String? attemptId) {
    if (_attemptId == attemptId) return;
    _attemptId = attemptId;
    _observation = NotificationOperatorObservation.uncertain;
    _evidence.clear();
  }

  void _clearSensitive() {
    _nativeContext?._invalidate();
    _nativeContext = null;
    _claim = null;
    _content = null;
    _confirmation = null;
    _checked = false;
    for (final reference in _references) {
      reference.original = null;
    }
  }

  void _invalidate({bool authority = false, bool departure = false}) {
    _generation++;
    _loadGeneration++;
    _authorityLost |= authority;
    _departed |= departure;
    _clearSensitive();
    _page = null;
    _loading = false;
    _deadline?.cancel();
    if (mounted) {
      setState(
        () => _message = authority || departure
            ? 'This page left its original session or navigation. Reopen assisted SMS to continue.'
            : 'Sensitive review cleared while the app was out of the foreground. Refresh to continue.',
      );
    }
  }

  void _scheduleDeadline() {
    _deadline?.cancel();
    final user = _session.user;
    final deadlines = [
      if (user != null) user.expiresAt,
      if (user?.sensitiveVerificationAt != null)
        user!.sensitiveVerificationAt!.add(const Duration(minutes: 5)),
      if (_claim != null) _claim!.claimExpiresAt,
      if (_confirmation != null) _confirmation!.expiresAt,
    ]..sort();
    if (deadlines.isEmpty) return;
    final duration = deadlines.first.difference(DateTime.now());
    _deadline = Timer(duration.isNegative ? Duration.zero : duration, () {
      if (!mounted) return;
      if (!_api.canRead) {
        _invalidate(authority: true);
      } else {
        _generation++;
        _clearSensitive();
        setState(
          () => _message =
              'The claim or confirmation expired. Refresh pending jobs.',
        );
        _scheduleDeadline();
      }
    });
  }

  void _restore() {
    if (_restored || !_current || !_api.canManage) return;
    _restored = true;
    try {
      final checkpoints = ref
          .read(adminPendingAttemptStoreProvider)
          .restoreFamily(
            family: _family,
            permission: 'assisted_sms.manage',
            schema: _schema,
          );
      for (final entry in checkpoints) {
        final action = entry.intent['action'],
            resource = entry.intent['resource_id'];
        if (!_uuid.hasMatch(entry.requestKey) ||
            action is! String ||
            !_actions.contains(action) ||
            resource is! String ||
            !_uuid.hasMatch(resource) ||
            entry.resourceId != resource) {
          throw const FormatException(
            'Unverified operation recovery reference.',
          );
        }
        if (!_references.any(
          (reference) => reference.requestId == entry.requestKey,
        )) {
          _references.add(_Reference(entry.requestKey, action, resource));
        }
      }
      if (checkpoints.isNotEmpty) {
        _message =
            'Original operation references recovered. Check each operation before another change.';
      }
    } catch (_) {
      _message =
          'Recovery references could not be verified. Check the server record before continuing.';
      _authorityLost = true;
    }
    setState(() {});
  }

  Future<void> _load() async {
    if (!_current || _busy) return;
    final generation = ++_loadGeneration, task = _generation;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _api.listPending(cursor: _cursor);
      if (_taskCurrent(task) && generation == _loadGeneration) {
        setState(() => _page = page);
      }
    } catch (error) {
      if (_taskCurrent(task) && generation == _loadGeneration) {
        setState(() => _loadError = _error(error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<T?> _mutate<T>(
    NotificationOperatorOperation operation,
    Future<T> Function() dispatch,
  ) async {
    if (!_canMutate) return null;
    final task = _generation;
    final reference = _Reference(
      operation.requestId,
      operation.action,
      operation.resourceId,
      original: operation,
    );
    setState(() {
      _busy = true;
      _message = null;
      _references.add(reference);
    });
    final store = ref.read(adminPendingAttemptStoreProvider);
    var retained = false;
    try {
      store.retain(
        family: _family,
        resourceId: operation.resourceId,
        requestKey: operation.requestId,
        permission: 'assisted_sms.manage',
        intent: {
          'action': operation.action,
          'resource_id': operation.resourceId,
        },
        schema: _schema,
      );
      retained = true;
      if (!store.storageAvailable) {
        reference.unresolved = false;
        reference.status = 'Not submitted: recovery storage unavailable';
        throw const AdminAccountException(
          'Recovery storage is unavailable. No request was submitted.',
        );
      }
      if (!_taskCurrent(task)) return null;
      final value = await dispatch();
      if (!_taskCurrent(task)) return null;
      reference.unresolved = false;
      reference.status = 'Recorded';
      reference.original = null;
      if (value is NotificationOperatorReceipt) {
        reference.receipt = _receiptFacts(value);
      }
      store.clear(family: _family, resourceId: operation.resourceId);
      setState(
        () => _message =
            'The original ${_actionLabel(operation.action).toLowerCase()} operation was recorded.',
      );
      return value;
    } catch (error) {
      if (!_taskCurrent(task)) return null;
      // A post-dispatch 4xx can follow a committed mutation whose final
      // authority check failed. Only local, pre-dispatch failures prove that
      // this original UUID was never submitted.
      if (!operation.dispatched) {
        reference.unresolved = false;
        reference.original = null;
        reference.status = 'Not submitted';
        if (retained) {
          store.clear(family: _family, resourceId: operation.resourceId);
        } else {
          // A failed retain may mean an older original reference already owns
          // this resource. Never remove that older checkpoint as cleanup for
          // a command which did not dispatch.
          _restored = false;
          _restore();
        }
      } else {
        reference.status = 'Outcome unknown: check this original operation';
        _clearSensitive();
      }
      setState(() => _message = _error(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimJob(NotificationOperatorPendingJob job) async {
    if (!_canMutate) return;
    try {
      final operation = _api.prepareClaim(job, workerId: _workerId);
      final claim = await _mutate(operation, () => _api.claim(operation));
      if (claim == null || !_current) return;
      setState(() {
        _clearSensitive();
        _claim = claim;
      });
      _scheduleDeadline();
      await _getContent();
    } catch (error) {
      if (_current) setState(() => _message = _error(error));
    }
  }

  Future<void> _getContent() async {
    final claim = _claim;
    if (!_current || !_api.canManage || _busy || claim == null || _unresolved) {
      return;
    }
    final task = _generation;
    setState(() => _busy = true);
    try {
      final content = await _api.getClaimed(claim);
      if (_taskCurrent(task)) {
        setState(() {
          _content = content;
          _checked = false;
        });
      }
    } catch (error) {
      if (_taskCurrent(task)) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final content = _content;
    if (!_canMutate || content == null || !_checked) return;
    try {
      final operation = _api.prepareConfirm(content, userConfirmation: true);
      final confirmation = await _mutate(
        operation,
        () => _api.confirm(operation),
      );
      if (confirmation != null && _current) {
        setState(() => _confirmation = confirmation);
      }
      _scheduleDeadline();
    } catch (error) {
      if (_current) setState(() => _message = _error(error));
    }
  }

  Future<void> _release() async {
    final claim = _claim;
    if (!_canMutate || claim == null) return;
    try {
      final operation = _api.prepareRelease(claim);
      final receipt = await _mutate(
        operation,
        () => _api.releaseClaim(operation),
      );
      if (receipt != null && _current) {
        setState(_clearSensitive);
        _scheduleDeadline();
        await _load();
      }
    } catch (error) {
      if (_current) setState(() => _message = _error(error));
    }
  }

  Future<void> _start() async {
    final adapter = widget.assistedSmsAdapter,
        confirmation = _confirmation,
        content = _content;
    if (!_canMutate ||
        adapter == null ||
        confirmation == null ||
        content == null) {
      return;
    }
    final task = _generation;
    try {
      final operation = _api.prepareSendStart(confirmation);
      final start = await _mutate(
        operation,
        () => _api.recordSendStart(operation),
      );
      if (start == null || !_taskCurrent(task)) return;
      setState(() => _selectAttempt(start.attemptId));
      final permit = start.permit;
      if (permit == null) {
        _clearSensitive();
        setState(
          () => _message =
              'A start was already recorded. Sending authority was not reissued. Record an observation.',
        );
        return;
      }
      final nativeContext = NotificationOperatorNativeSendContext._(
        NotificationOperatorNativePayload._(
          start.attemptId,
          content.destinationE164,
          content.messageBody,
        ),
        permit,
        () => _taskCurrent(task) && _api.canManage,
      );
      _nativeContext = nativeContext;
      setState(() {
        _busy = true;
        _claim = null;
        _content = null;
        _confirmation = null;
        _checked = false;
      });
      NotificationOperatorAdapterObservation? observation;
      try {
        observation = await adapter.sendOnce(nativeContext);
      } catch (_) {
        if (_taskCurrent(task)) {
          setState(
            () => _message =
                'The native result is unknown. Record an observation using retained evidence.',
          );
        }
      } finally {
        nativeContext._invalidate();
        _nativeContext = null;
        if (mounted) setState(() => _busy = false);
      }
      if (!_taskCurrent(task) || observation == null) return;
      _observation = observation.observation;
      _evidence.text = observation.evidenceReferenceSha256;
      await _recordOutcome();
    } catch (error) {
      if (_taskCurrent(task)) setState(() => _message = _error(error));
    }
  }

  Future<void> _recordOutcome() async {
    final attempt = _attemptId;
    if (!_canMutate || attempt == null) return;
    try {
      final operation = _api.prepareOutcome(
        attemptId: attempt,
        observation: _observation,
        evidenceReferenceSha256: _evidence.text.trim(),
      );
      final outcome = await _mutate(
        operation,
        () => _api.recordOutcome(operation),
      );
      if (outcome != null && _current) {
        setState(() {
          _selectAttempt(null);
        });
        await _load();
      }
    } catch (error) {
      if (_current) setState(() => _message = _error(error));
    }
  }

  Future<void> _check(_Reference reference) async {
    if (!_current || !_api.canManage || _busy) return;
    final task = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _api.getOperation(
        reference.requestId,
        originalOperation: reference.original,
      );
      if (!_taskCurrent(task)) return;
      final receipt = result.receipt;
      if (receipt == null) {
        reference.status = 'No recorded result yet: keep this original UUID';
      } else {
        final resource = receipt is NotificationOperatorOutcome
            ? receipt.attemptId
            : receipt.jobId;
        if (reference.action.isNotEmpty &&
            (receipt.action != reference.action ||
                resource != reference.resourceId)) {
          throw const FormatException(
            'The recorded operation does not match its retained reference.',
          );
        }
        reference.unresolved = false;
        reference.original = null;
        reference.status = 'Recorded result recovered: no sending authority';
        reference.receipt = _receiptFacts(receipt);
        if (receipt is NotificationOperatorSendStart) {
          _selectAttempt(receipt.attemptId);
        }
        // A recovered claim or confirmation is history only. It is never
        // adopted for content retrieval, confirmation or a send start.
        ref
            .read(adminPendingAttemptStoreProvider)
            .clear(family: _family, resourceId: reference.resourceId);
      }
      setState(() {});
    } catch (error) {
      if (_taskCurrent(task)) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _lookupOperation() {
    final id = _lookup.text.trim();
    if (!_uuid.hasMatch(id)) {
      setState(() => _message = 'Enter the original operation UUID.');
      return;
    }
    final existing = _references
        .where((reference) => reference.requestId == id)
        .firstOrNull;
    if (existing != null) {
      unawaited(_check(existing));
      return;
    }
    // A status lookup is not a dispatched mutation. A mistyped UUID must not
    // manufacture an unresolved pending write or block a genuine operation.
    final reference = _Reference(id, '', '')..unresolved = false;
    setState(() => _references.add(reference));
    unawaited(_check(reference));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cloudflareAdminSessionProvider);
    final store = ref.watch(adminPendingAttemptStoreProvider);
    final allowed = _current;
    return AdminPage(
      title: 'Assisted SMS',
      trailing: IconButton(
        tooltip: 'Refresh pending SMS jobs',
        onPressed: allowed && !_busy && !_loading ? _load : null,
        icon: const Icon(Icons.refresh, size: 26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!allowed) ...[
            _Message(
              _session.user?.usesEmailVerification == true
                  ? 'Assisted SMS requires current access and recent email verification.'
                  : 'Assisted SMS requires the original current session, assisted_sms.read access and fresh authenticator verification.',
              error: true,
            ),
            if (_session.user?.usesEmailVerification == true &&
                _session.user!.permissions.contains('assisted_sms.read'))
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => context.go(
                        Uri(
                          path: '/admin/security/verify-email',
                          queryParameters: {
                            'returnTo': GoRouterState.of(
                              context,
                            ).uri.toString(),
                          },
                        ).toString(),
                      ),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Verify email'),
              ),
          ] else ...[
            if (!_api.canManage)
              const _Message(
                'Read-only access. Managing assisted SMS requires assisted_sms.manage and fresh verification.',
              ),
            if (!store.storageAvailable)
              _Message(store.storageMessage, error: true),
            if (_message != null) _Message(_message!),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Assisted SMS operation in progress',
              ),
            if (_references.isNotEmpty) ...[
              _heading(context, 'Original operations'),
              AdminDataTable(
                tableLabel: 'Assisted SMS operation references',
                rows: [
                  for (final reference in _references)
                    _row(reference.requestId, {
                      'request_id': reference.requestId,
                      'action': _actionLabel(reference.action),
                      'resource_id': reference.resourceId,
                      'status': reference.status,
                    }),
                ],
                columns: [
                  _column('request_id', 'Original UUID'),
                  _column('action', 'Action'),
                  _column('resource_id', 'Resource ID'),
                  _column('status', 'Status'),
                ],
                trailingBuilder: (row) => OutlinedButton.icon(
                  onPressed: !_busy && _api.canManage
                      ? () => _check(
                          _references.firstWhere((r) => r.requestId == row.id),
                        )
                      : null,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check operation'),
                ),
              ),
              for (final reference in _references.where(
                (reference) => reference.receipt.isNotEmpty,
              ))
                AdminRecordFactsTable(
                  fields: [
                    ('Original UUID', reference.requestId),
                    ...reference.receipt,
                  ],
                  semanticLabel: 'Recorded operation ${reference.requestId}',
                ),
            ],
            if (_api.canManage) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _lookup,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Original operation UUID',
                ),
                onSubmitted: (_) => _lookupOperation(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _lookupOperation,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Check original UUID'),
                ),
              ),
            ],
            _heading(context, 'Pending jobs'),
            if (_loading)
              const AdminLoadingState(title: 'Loading assisted SMS jobs')
            else if (_loadError != null)
              _Message(_loadError!, error: true)
            else if (_page != null) ...[
              if (_page!.items.isEmpty)
                const _Message('No pending assisted SMS jobs on this page.'),
              AdminDataTable(
                tableLabel: 'Pending assisted SMS jobs',
                rows: [
                  for (final job in _page!.items)
                    _row(job.id, {
                      'id': job.id,
                      'payment_id': job.paymentId,
                      'state': job.state.wireValue,
                      'created_at': adminKigaliDateTime(job.createdAt),
                      'fence': job.fence,
                      'attempt_id': job.attemptId ?? '—',
                    }),
                ],
                columns: [
                  _column('id', 'Job ID'),
                  _column('payment_id', 'Payment ID'),
                  _column('state', 'State'),
                  _column('created_at', 'Created'),
                  _column('fence', 'Fence'),
                  _column('attempt_id', 'Attempt ID'),
                ],
                trailingBuilder: (row) {
                  final job = _page!.items.firstWhere(
                    (job) => job.id == row.id,
                  );
                  return job.attemptId != null
                      ? TextButton.icon(
                          onPressed: !_busy && _api.canManage
                              ? () => setState(
                                  () => _selectAttempt(job.attemptId),
                                )
                              : null,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Record observation'),
                        )
                      : TextButton.icon(
                          onPressed: _canMutate && _claim == null
                              ? () => _claimJob(job)
                              : null,
                          icon: const Icon(Icons.assignment_ind_outlined),
                          label: const Text('Claim for review'),
                        );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: !_busy && _previous.isNotEmpty
                        ? () {
                            setState(() => _cursor = _previous.removeLast());
                            unawaited(_load());
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous jobs'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_busy && _page!.nextCursor != null
                        ? () {
                            setState(() {
                              _previous.add(_cursor);
                              _cursor = _page!.nextCursor;
                            });
                            unawaited(_load());
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next jobs'),
                  ),
                ],
              ),
            ],
            if (_claim != null) ...[
              _heading(context, 'Exact-content review'),
              AdminRecordFactsTable(
                semanticLabel: 'Current assisted SMS claim',
                fields: [
                  ('Job ID', _claim!.jobId!),
                  (
                    'Lease expires',
                    adminKigaliDateTime(_claim!.claimExpiresAt),
                  ),
                  ('Fence', '${_claim!.fenceVersion}'),
                  if (_content != null) ...[
                    ('Exact recipient', _content!.destinationE164),
                    ('Exact message', _content!.messageBody),
                    ('Recipient SHA-256', _content!.destinationSha256),
                    ('Content SHA-256', _content!.bodySha256),
                    (
                      'Destination revision',
                      '${_content!.destinationRevision}',
                    ),
                    ('Template', _content!.templateKey),
                  ],
                ],
              ),
              if (_content == null)
                TextButton.icon(
                  onPressed: !_busy && !_unresolved ? _getContent : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Load exact content'),
                ),
              if (_content != null && _confirmation == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I checked this exact recipient and message',
                  ),
                  value: _checked,
                  onChanged: _canMutate
                      ? (value) => setState(() => _checked = value == true)
                      : null,
                ),
              if (_confirmation != null)
                const _Message(
                  'Exact recipient and message confirmed for this original session.',
                ),
              if (widget.assistedSmsAdapter == null)
                const _Message(
                  'Native SMS adapter is unavailable. Sending is disabled; release the claim when review is complete.',
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _canMutate &&
                            _checked &&
                            _content != null &&
                            _confirmation == null
                        ? _confirm
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm exact content'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _canMutate &&
                            _confirmation != null &&
                            widget.assistedSmsAdapter != null
                        ? _start
                        : null,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Record start and send once'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _canMutate ? _release : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Release claim'),
                  ),
                ],
              ),
            ],
            if (_attemptId != null && _api.canManage) ...[
              _heading(context, 'Record observed outcome'),
              AdminRecordFactsTable(
                semanticLabel: 'Assisted SMS attempt',
                fields: [('Attempt ID', _attemptId!)],
              ),
              const Text(
                'An observation does not confirm provider delivery or financial settlement.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<NotificationOperatorObservation>(
                key: ValueKey(_attemptId),
                initialValue: _observation,
                decoration: const InputDecoration(
                  labelText: 'Observed outcome',
                ),
                isExpanded: true,
                items: [
                  for (final value in NotificationOperatorObservation.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_observationLabel(value)),
                    ),
                ],
                onChanged: _canMutate
                    ? (value) {
                        if (value != null) setState(() => _observation = value);
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _evidence,
                enabled: _canMutate,
                decoration: const InputDecoration(
                  labelText: 'Evidence reference SHA-256',
                  helperText: '64 lowercase hexadecimal characters',
                ),
                onChanged: (_) => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed:
                      _canMutate &&
                          RegExp(
                            r'^[a-f0-9]{64}$',
                          ).hasMatch(_evidence.text.trim())
                      ? _recordOutcome
                      : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Record observation'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _clearSensitive();
    _deadline?.cancel();
    _subscription.close();
    _router?.routerDelegate.removeListener(_navigationChanged);
    _secondaryAnimation?.removeStatusListener(_routeStatus);
    WidgetsBinding.instance.removeObserver(this);
    _lookup.dispose();
    _evidence.dispose();
    super.dispose();
  }
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 24, bottom: 12),
  child: Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  ),
);
AdminTableRowData _row(String id, Map<String, dynamic> fields) =>
    AdminTableRowData(
      id: id,
      title: id,
      subtitle: '',
      status: '',
      amount: '',
      extra: fields,
    );
AdminTableColumn _column(String field, String label) => AdminTableColumn(
  label: label,
  selectable: true,
  value: (row) => '${row.extra[field] ?? '—'}',
);
String _actionLabel(String action) => switch (action) {
  'claim' => 'Claim',
  'confirm' => 'Confirm exact content',
  'record_send_start' => 'Record send start',
  'release_claim' => 'Release claim',
  'record_outcome' => 'Record observation',
  '' => 'Original UUID lookup',
  _ => action,
};
String _observationLabel(NotificationOperatorObservation value) =>
    switch (value) {
      NotificationOperatorObservation.observedSent => 'Observed sent',
      NotificationOperatorObservation.failedNoSend => 'Failed — no send',
      NotificationOperatorObservation.uncertain => 'Uncertain',
    };
String _error(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The response or operation reference could not be verified. Check the original operation.'
    : 'The operation could not be completed. Check its original UUID before another change.';
List<(String, String)> _receiptFacts(NotificationOperatorReceipt receipt) => [
  ('Recorded action', _actionLabel(receipt.action)),
  if (receipt.jobId != null) ('Job ID', receipt.jobId!),
  if (receipt is NotificationOperatorSendStart)
    ('Attempt ID', receipt.attemptId),
  if (receipt is NotificationOperatorOutcome) ...[
    ('Attempt ID', receipt.attemptId),
    ('Observation', _observationLabel(receipt.observation)),
    ('Evidence reference SHA-256', receipt.evidenceReferenceSha256),
  ],
  ('Delivery confirmed', 'No'),
  ('Provider confirmation', 'No'),
  ('Settlement', 'Not asserted'),
];

class _Message extends StatelessWidget {
  const _Message(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}
