import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/momo_sms_sync_status.dart';
import '../providers/momo_sms_sync_providers.dart';
import '../services/momo_sms_autoread_service.dart';

class MomoSmsSyncStatusCard extends ConsumerStatefulWidget {
  const MomoSmsSyncStatusCard({
    this.compact = false,
    this.onSyncComplete,
    this.onManageAccess,
    this.onOpenStatements,
    super.key,
  });

  final bool compact;
  final ValueChanged<MomoInboxSyncResult>? onSyncComplete;
  final Future<void> Function()? onManageAccess;
  final VoidCallback? onOpenStatements;

  @override
  ConsumerState<MomoSmsSyncStatusCard> createState() =>
      _MomoSmsSyncStatusCardState();
}

class _MomoSmsSyncStatusCardState extends ConsumerState<MomoSmsSyncStatusCard>
    with WidgetsBindingObserver {
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    ref.invalidate(momoSmsAccessSnapshotProvider);
    ref.invalidate(momoSmsSyncStatusProvider);
  }

  Future<void> _enableAndSync() async {
    if (_isWorking) {
      return;
    }

    setState(() => _isWorking = true);
    try {
      await ref
          .read(appAccessServiceProvider)
          .enableAndRequest(AppAccessPermission.sms);
      ref.invalidate(momoSmsAccessSnapshotProvider);

      final service = ref.read(momoSmsAutoreadServiceProvider);
      await service.refresh(forcePermissionRequest: true);
      try {
        final result = await service.syncInbox(
          trigger: MomoInboxSyncTrigger.manual,
        );
        ref.invalidate(momoSmsSyncStatusProvider);
        widget.onSyncComplete?.call(result);
        if (!mounted) {
          return;
        }
        CoolToast.success(
          context,
          result.uploadedMessages > 0
              ? 'SMS sync complete'
              : 'SMS access enabled',
        );
      } on MomoSmsSyncException catch (error) {
        if (error.message != 'Sync already running') {
          rethrow;
        }
        ref.invalidate(momoSmsSyncStatusProvider);
        if (!mounted) {
          return;
        }
        CoolToast.info(context, 'Initial sync started');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(
        context,
        error is MomoSmsSyncException ? error.message : 'SMS enable failed',
      );
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _syncNow() async {
    if (_isWorking) {
      return;
    }

    setState(() => _isWorking = true);
    try {
      final result = await ref
          .read(momoSmsAutoreadServiceProvider)
          .syncInbox(trigger: MomoInboxSyncTrigger.manual);
      ref.invalidate(momoSmsSyncStatusProvider);
      widget.onSyncComplete?.call(result);
      if (!mounted) {
        return;
      }
      if (result.uploadedMessages > 0) {
        CoolToast.success(context, 'SMS sync complete');
      } else {
        CoolToast.info(context, 'No new SMS found');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(
        context,
        error is MomoSmsSyncException ? error.message : 'SMS sync failed',
      );
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _manageAccess() async {
    if (_isWorking) {
      return;
    }

    if (widget.onManageAccess == null) {
      return;
    }

    setState(() => _isWorking = true);
    try {
      await widget.onManageAccess!.call();
      ref.invalidate(momoSmsAccessSnapshotProvider);
      ref.invalidate(momoSmsSyncStatusProvider);
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final accessSnapshotAsync = ref.watch(momoSmsAccessSnapshotProvider);
    final syncStatusAsync = ref.watch(momoSmsSyncStatusProvider);

    final accessSnapshot = accessSnapshotAsync.valueOrNull;
    final syncStatus = syncStatusAsync.valueOrNull ?? const MomoSmsSyncStatus();

    final title = _titleFor(accessSnapshot, syncStatus, context);
    final subtitle = _subtitleFor(accessSnapshot, syncStatus, context);
    final chips = _buildChips(syncStatus);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: widget.compact ? 42 : 46,
                height: widget.compact ? 42 : 46,
                decoration: BoxDecoration(
                  color: colors.accentGlow,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.sms_rounded,
                  color: colors.accent,
                  size: widget.compact ? 20 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    SizedBox(height: space.x1),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
          const SizedBox(height: 14),
          _ActionRow(
            isWorking: _isWorking,
            primaryLabel: _primaryLabelFor(accessSnapshot, syncStatus, context),
            onPrimaryTap: () {
              switch (accessSnapshot?.kind) {
                case AppAccessStateKind.ready:
                  unawaited(_syncNow());
                  return;
                case AppAccessStateKind.disabledInApp:
                case AppAccessStateKind.needsSystemPermission:
                  unawaited(_enableAndSync());
                  return;
                case AppAccessStateKind.blockedInSystem:
                  unawaited(_manageAccess());
                  return;
                case AppAccessStateKind.notAvailable:
                case AppAccessStateKind.serviceDisabled:
                case null:
                  return;
              }
            },
            secondaryLabel:
                widget.onOpenStatements != null && syncStatus.hasHistory
                ? context.l10n.statements
                : (widget.onManageAccess != null &&
                          accessSnapshot?.kind != AppAccessStateKind.ready
                      ? context.l10n.profileAppAccess
                      : null),
            onSecondaryTap:
                widget.onOpenStatements != null && syncStatus.hasHistory
                ? widget.onOpenStatements
                : widget.onManageAccess != null &&
                      accessSnapshot?.kind != AppAccessStateKind.ready
                ? () {
                    _manageAccess();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

List<Widget> _buildChips(MomoSmsSyncStatus status) {
  final chips = <Widget>[];
  final latest = status.latestSuccessfulRun;
  if (status.initialBackfillCompleted) {
    chips.add(const _SyncChip(label: '12-month backfill'));
  }
  if (latest != null && latest.incremental) {
    chips.add(const _SyncChip(label: 'Incremental sync'));
  }
  if (latest != null && latest.uploadedMessages > 0) {
    chips.add(_SyncChip(label: '+${latest.uploadedMessages} new'));
  }
  if (latest != null && latest.duplicateMessages > 0) {
    chips.add(_SyncChip(label: '${latest.duplicateMessages} duplicates'));
  }
  return chips;
}

String _titleFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      if (!status.initialBackfillCompleted) {
        return 'Import past year';
      }
      return 'SMS sync ready';
    case AppAccessStateKind.disabledInApp:
      return 'SMS sync off';
    case AppAccessStateKind.needsSystemPermission:
      return 'Allow SMS access';
    case AppAccessStateKind.blockedInSystem:
      return 'SMS blocked';
    case AppAccessStateKind.notAvailable:
      return 'SMS unavailable';
    case AppAccessStateKind.serviceDisabled:
      return 'SMS unavailable';
    case null:
      return 'SMS sync';
  }
}

String _subtitleFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  final latest = status.latestRun;
  final dateFormat = DateFormat('dd MMM, HH:mm');
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      if (!status.initialBackfillCompleted) {
        return 'Run a one-time 12-month import of approved M-Money confirmations.';
      }
      if (latest?.isFailed == true) {
        return latest?.errorMessage?.trim().isNotEmpty == true
            ? 'Last sync failed: ${latest!.errorMessage!}'
            : 'Last sync failed. Try again to refresh approved confirmations.';
      }
      final completedAt =
          status.latestSuccessfulRun?.scanCompletedAt ??
          status.latestSuccessfulRun?.scanStartedAt;
      if (completedAt != null) {
        return 'Approved sender IDs only. Last synced ${dateFormat.format(completedAt.toLocal())}.';
      }
      return 'Approved sender IDs only. New confirmations sync into your ledger.';
    case AppAccessStateKind.disabledInApp:
      return 'Turn this on only if you want Cool to read approved M-Money confirmations.';
    case AppAccessStateKind.needsSystemPermission:
      return 'Grant Android SMS access to verify Mobile Money payments automatically.';
    case AppAccessStateKind.blockedInSystem:
      return 'Android blocked SMS access. Open settings to continue historical sync.';
    case AppAccessStateKind.notAvailable:
      return 'Automatic M-Money SMS sync is available on Android only.';
    case AppAccessStateKind.serviceDisabled:
      return 'Automatic SMS sync is currently unavailable on this device.';
    case null:
      if (latest?.isFailed == true && latest?.errorMessage != null) {
        return latest!.errorMessage!;
      }
      return 'Checking SMS access and sync history.';
  }
}

String? _primaryLabelFor(
  AppAccessSnapshot? snapshot,
  MomoSmsSyncStatus status,
  BuildContext context,
) {
  switch (snapshot?.kind) {
    case AppAccessStateKind.ready:
      return 'Sync now';
    case AppAccessStateKind.disabledInApp:
    case AppAccessStateKind.needsSystemPermission:
      return 'Enable SMS';
    case AppAccessStateKind.blockedInSystem:
      return 'Open access';
    case AppAccessStateKind.notAvailable:
    case AppAccessStateKind.serviceDisabled:
      return null;
    case null:
      return null;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isWorking,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  final bool isWorking;
  final String? primaryLabel;
  final VoidCallback? onPrimaryTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    if (primaryLabel == null && secondaryLabel == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (secondaryLabel != null && onSecondaryTap != null)
          Expanded(
            child: CoolButton(
              label: secondaryLabel!,
              variant: CoolButtonVariant.secondary,
              onTap: onSecondaryTap!,
            ),
          ),
        if (secondaryLabel != null &&
            onSecondaryTap != null &&
            primaryLabel != null &&
            onPrimaryTap != null)
          const SizedBox(width: 10),
        if (primaryLabel != null && onPrimaryTap != null)
          Expanded(
            child: CoolButton(
              label: primaryLabel!,
              isLoading: isWorking,
              onTap: onPrimaryTap!,
            ),
          ),
      ],
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2 - 1,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}
