import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/models/contribution_record_copy.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../status/native_permission_sheets.dart';
import 'receipt_sms_consent_section.dart';
import 'settings_subpage_widgets.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

enum _PreferenceOperation { save, refresh }

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  _PreferenceOperation? _activeOperation;
  int _operationEpoch = 0;
  String? _operationError;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repository = ref.read(collectRepositoryProvider.notifier);
    ref.listen(
      collectRepositoryProvider.select(
        (state) => (state.currentProfile?.id, repository.sessionGeneration),
      ),
      (previous, next) {
        if (!mounted || previous == next) return;
        _operationEpoch++;
        setState(() {
          _activeOperation = null;
          _operationError = null;
        });
      },
    );
    final preferences = state.notificationPreferences;
    final pending = repository.pendingNotificationPreferences;
    final needsRefresh = repository.notificationPreferencesNeedsRefresh;
    final busy = _activeOperation != null;
    final canEdit =
        state.currentProfile != null &&
        !busy &&
        !needsRefresh &&
        pending == null;
    return ScreenScaffold(
      title: 'Notifications',
      showHeader: false,
      compact: true,
      topChrome: const SettingsSubpageHeader(title: 'Notifications'),
      children: [
        if (busy)
          Semantics(
            liveRegion: true,
            label: _activeOperation == _PreferenceOperation.refresh
                ? 'Refreshing notification preferences'
                : 'Saving notification preferences',
            child: const LinearProgressIndicator(),
          ),
        if (needsRefresh || _operationError != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _operationError ??
                  (pending == null
                      ? 'Connect and refresh to load your saved preferences before changing them.'
                      : 'Your change was not confirmed. Refresh to review the latest saved preferences before trying again.'),
            ),
          ),
        if (needsRefresh || pending != null)
          CollectButton(
            label: 'Refresh preferences',
            icon: CollectIcons.sync,
            variant: CollectButtonVariant.secondary,
            onPressed: state.currentProfile == null || busy ? null : _refresh,
            expand: true,
          ),
        if (pending != null) ...[
          const SectionHeader(title: 'Pending change'),
          Text(
            needsRefresh
                ? 'Your intended preferences are retained. Refresh before reviewing and saving them.'
                : 'Review your intended preferences against the saved preferences below. Saving applies every intended preference.',
          ),
          SettingsOptionPanel(
            children: [
              for (final item in [
                (
                  ContributionRecordCopy.channelTitle,
                  preferences.contributionConfirmations,
                  pending.contributionConfirmations,
                ),
                (
                  'Contribution reminders',
                  preferences.paymentReminders,
                  pending.paymentReminders,
                ),
                (
                  'Group updates',
                  preferences.groupUpdates,
                  pending.groupUpdates,
                ),
                (
                  'Security notices',
                  preferences.securityNotices,
                  pending.securityNotices,
                ),
                (
                  'Email contribution records',
                  preferences.emailEnabled,
                  pending.emailEnabled,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.all(CollectSpacing.x3),
                  child: Text(
                    needsRefresh
                        ? '${item.$1}: intended ${item.$3 ? 'On' : 'Off'}'
                        : '${item.$1}: saved ${item.$2 ? 'On' : 'Off'}, intended ${item.$3 ? 'On' : 'Off'}',
                  ),
                ),
            ],
          ),
          CollectButton(
            label: 'Save pending change',
            onPressed: state.currentProfile == null || busy || needsRefresh
                ? null
                : () => _save(pending),
            expand: true,
          ),
          CollectButton(
            label: 'Discard pending change',
            variant: CollectButtonVariant.subtle,
            onPressed: busy ? null : _discard,
            expand: true,
          ),
        ],
        SettingsOptionPanel(
          children: [
            SettingsSwitchRow(
              title: 'Email contribution records',
              subtitle:
                  'Send contribution records to your verified account email when contribution confirmations are enabled.',
              value: preferences.emailEnabled,
              onChanged: !canEdit
                  ? null
                  : (value) => _save(preferences.copyWith(emailEnabled: value)),
            ),
            SettingsSwitchRow(
              title: ContributionRecordCopy.channelTitle,
              subtitle: ContributionRecordCopy.channelDescription,
              value: preferences.contributionConfirmations,
              onChanged: !canEdit
                  ? null
                  : (value) => _save(
                      preferences.copyWith(contributionConfirmations: value),
                    ),
            ),
            SettingsSwitchRow(
              title: 'Contribution reminders',
              subtitle: 'Pending contribution reminders before expiry.',
              value: preferences.paymentReminders,
              onChanged: !canEdit
                  ? null
                  : (value) =>
                        _save(preferences.copyWith(paymentReminders: value)),
            ),
            SettingsSwitchRow(
              title: 'Group updates',
              subtitle: 'Membership and group-management changes.',
              value: preferences.groupUpdates,
              onChanged: !canEdit
                  ? null
                  : (value) => _save(preferences.copyWith(groupUpdates: value)),
            ),
            SettingsSwitchRow(
              title: 'Security notices',
              subtitle: 'Important account and privacy alerts.',
              value: preferences.securityNotices,
              onChanged: !canEdit
                  ? null
                  : (value) =>
                        _save(preferences.copyWith(securityNotices: value)),
            ),
          ],
        ),
        ReceiptSmsConsentSection(
          key: ValueKey((
            'receipt-sms',
            state.currentProfile?.id,
            repository.sessionGeneration,
          )),
        ),
        CollectButton(
          label: 'Review phone permission',
          icon: CollectIcons.settings,
          variant: CollectButtonVariant.secondary,
          onPressed: () => showNotificationSettingsSheet(context, ref),
          expand: true,
        ),
      ],
    );
  }

  Future<void> _save(NotificationPreferences preferences) =>
      _run(_PreferenceOperation.save, (repository) {
        return repository.updateNotificationPreferences(preferences);
      });

  Future<void> _refresh() => _run(
    _PreferenceOperation.refresh,
    (repository) => repository.refreshNotificationPreferences(),
  );

  Future<void> _run(
    _PreferenceOperation operation,
    Future<void> Function(CollectRepository) request,
  ) async {
    if (_activeOperation != null) return;
    final epoch = ++_operationEpoch;
    setState(() {
      _activeOperation = operation;
      _operationError = null;
    });
    try {
      await request(ref.read(collectRepositoryProvider.notifier));
    } catch (_) {
      if (!mounted || epoch != _operationEpoch) return;
      setState(() {
        _operationError = switch (operation) {
          _PreferenceOperation.save =>
            'Your change was not confirmed. Refresh preferences before trying again.',
          _PreferenceOperation.refresh =>
            'Could not refresh preferences. Connect and try Refresh again.',
        };
      });
    } finally {
      if (mounted && epoch == _operationEpoch) {
        setState(() => _activeOperation = null);
      }
    }
  }

  void _discard() {
    try {
      ref
          .read(collectRepositoryProvider.notifier)
          .discardPendingNotificationPreferences();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Wait for the current save before discarding the change.',
          ),
        ),
      );
    }
  }
}
