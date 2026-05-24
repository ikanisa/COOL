import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/env/app_env.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ReceiverScreen extends ConsumerStatefulWidget {
  const ReceiverScreen({super.key});

  @override
  ConsumerState<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends ConsumerState<ReceiverScreen> {
  var _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final state = ref.watch(collectRepositoryProvider);
    final flagsEnabled = env.enableInternalReceiverMode && env.enableSmsReader;
    return ScreenScaffold(
      title: 'Receiver mode',
      subtitle:
          'Android SMS ingestion is restricted to internal builds with explicit consent. Manual paste works everywhere.',
      children: [
        ReceiverConsentCard(
          flagsEnabled: flagsEnabled,
          consented: state.receiverModeEnabled,
          isSyncing: _isSyncing,
          onConsentChanged: flagsEnabled
              ? (value) async => ref
                    .read(collectRepositoryProvider.notifier)
                    .setReceiverMode(value)
              : null,
          onManualPaste: () => context.go('/receiver/manual'),
          onSync: flagsEnabled && state.receiverModeEnabled && !_isSyncing
              ? () async {
                  setState(() => _isSyncing = true);
                  try {
                    final count = await ref
                        .read(collectRepositoryProvider.notifier)
                        .syncPendingReceiverSms();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          count == 0
                              ? 'No consented SMS waiting to sync.'
                              : 'Synced $count consented SMS message(s).',
                        ),
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _isSyncing = false);
                  }
                }
              : null,
        ),
      ],
    );
  }
}
