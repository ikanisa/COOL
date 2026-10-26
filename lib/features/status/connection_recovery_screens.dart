import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class OfflineRecoveryScreen extends StatelessWidget {
  const OfflineRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _RecoveryRoute(title: 'Connection');
}

class SyncRecoveryScreen extends StatelessWidget {
  const SyncRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _RecoveryRoute(title: 'Data sync');
}

// A route name is not a network probe. Read the actual data state, and discard
// this screen's attempt state whenever its repository or account changes.
class _RecoveryRoute extends ConsumerWidget {
  const _RecoveryRoute({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(collectRepositoryProvider.notifier);
    final identity = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile?.id),
    );
    return _ConnectionRecoveryScreen(
      key: ValueKey((title, repository, identity)),
      title: title,
    );
  }
}

class _ConnectionRecoveryScreen extends ConsumerStatefulWidget {
  const _ConnectionRecoveryScreen({required this.title, super.key});

  final String title;

  @override
  ConsumerState<_ConnectionRecoveryScreen> createState() =>
      _ConnectionRecoveryScreenState();
}

class _ConnectionRecoveryScreenState
    extends ConsumerState<_ConnectionRecoveryScreen> {
  bool _retrying = false;
  bool _retryFailed = false;
  DateTime? _failureBaseline;
  DateTime? _verifiedRefreshAt;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final busy = _retrying || state.isLoading;
    final failed =
        state.lastError != null ||
        (_retryFailed && state.lastSuccessfulSyncAt == _failureBaseline);
    final refreshed =
        !busy &&
        !failed &&
        !state.usingStaleCache &&
        _verifiedRefreshAt != null &&
        state.lastSuccessfulSyncAt == _verifiedRefreshAt;
    final smsAttention =
        state.smsSyncNeedsAttention || state.smsQueueOverflowed;
    final title = busy
        ? 'Refreshing data'
        : failed || state.usingStaleCache
        ? 'Updates unavailable'
        : refreshed
        ? 'Data refreshed'
        : 'Refresh your data';
    final message = busy
        ? 'Checking groups and recorded activity.'
        : failed
        ? 'Could not refresh data. Check your connection and try again.'
        : state.usingStaleCache
        ? 'Previously loaded data may be out of date.'
        : refreshed
        ? 'The latest data refresh completed. This does not confirm a payment.'
        : state.collections.isNotEmpty
        ? 'Loaded groups can be opened. Refresh to check for updates.'
        : 'Refresh to load groups and recorded activity.';

    final lastSync = state.lastSuccessfulSyncAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final lastSyncLabel = lastSync == null
        ? 'Last data refresh: Not available'
        : 'Last data refresh: ${localizations.formatMediumDate(lastSync)}, '
              '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastSync), alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat)}';

    return ScreenScaffold(
      title: widget.title,
      showHeader: false,
      compact: true,
      children: [
        CollectPlainPageHeader(title: widget.title),
        Semantics(
          liveRegion: true,
          child: MinimalStatePanel(
            icon: CollectIcons.sync,
            title: title,
            message: message,
            // Content may wrap at normal text size too; never hide a warning.
            titleMaxLines: 4,
            messageMaxLines: 10,
            contentMaxWidth: double.infinity,
            tone: failed || state.usingStaleCache
                ? CollectStatusTone.warning
                : CollectStatusTone.info,
            primaryAction: CollectButton(
              key: const ValueKey('recovery-refresh'),
              label: busy ? 'Refreshing data' : 'Refresh data',
              icon: CollectIcons.sync,
              onPressed: busy ? null : _retry,
              expand: true,
            ),
            secondaryAction: CollectButton(
              label: state.collections.isNotEmpty
                  ? 'View groups'
                  : 'Open groups',
              icon: CollectIcons.collections,
              onPressed: () => context.go('/groups'),
              variant: CollectButtonVariant.subtle,
              expand: true,
            ),
          ),
        ),
        Text(lastSyncLabel, style: Theme.of(context).textTheme.bodySmall),
        Text(
          'Refreshing does not resend payments or SMS updates.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (smsAttention) ...[
          Semantics(
            liveRegion: true,
            child: const Text(
              'SMS sync still needs attention. Review it in Settings.',
            ),
          ),
          CollectButton(
            label: 'Open settings',
            icon: CollectIcons.sync,
            onPressed: () => context.go('/settings'),
            variant: CollectButtonVariant.subtle,
            expand: true,
          ),
        ],
        CollectButton(
          label: 'Privacy',
          icon: CollectIcons.privacy,
          onPressed: () => context.go('/settings/legal/privacy'),
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _retry() async {
    if (!mounted) return;
    final before = ref.read(collectRepositoryProvider);
    // Guard the callback itself as well as the disabled button: two taps can
    // arrive before Flutter rebuilds, and a repository load may already be active.
    if (_retrying || before.isLoading) return;
    final repository = ref.read(collectRepositoryProvider.notifier);
    final identity = before.currentProfile?.id;
    setState(() {
      _retrying = true;
      _retryFailed = false;
      _verifiedRefreshAt = null;
    });
    try {
      // Refresh the data view only. Never replay a payment, intent or SMS queue.
      await repository.loadInitial(syncPendingSms: false);
      if (!_ownsAttempt(repository, identity)) return;
      final after = ref.read(collectRepositoryProvider);
      final syncedAt = after.lastSuccessfulSyncAt;
      // loadInitial handles its own errors and may also return without a load.
      // Completion of its Future, by itself, is not evidence of a refresh.
      final confirmed =
          !after.isLoading &&
          !after.usingStaleCache &&
          after.lastError == null &&
          syncedAt != null &&
          (before.lastSuccessfulSyncAt == null ||
              syncedAt.isAfter(before.lastSuccessfulSyncAt!));
      setState(() {
        _verifiedRefreshAt = confirmed ? syncedAt : null;
        _retryFailed = !confirmed;
        _failureBaseline = after.lastSuccessfulSyncAt;
      });
    } catch (_) {
      if (!_ownsAttempt(repository, identity)) return;
      setState(() {
        _retryFailed = true;
        _failureBaseline = ref
            .read(collectRepositoryProvider)
            .lastSuccessfulSyncAt;
      });
      // Raw backend exceptions can contain identifiers or request details.
      // Only the fixed recovery message above is presented to the member.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  bool _ownsAttempt(CollectRepository repository, String? identity) {
    if (!mounted) return false;
    return identical(
          repository,
          ref.read(collectRepositoryProvider.notifier),
        ) &&
        ref.read(collectRepositoryProvider).currentProfile?.id == identity;
  }
}
