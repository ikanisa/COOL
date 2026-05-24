import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ManualSmsScreen extends ConsumerStatefulWidget {
  const ManualSmsScreen({super.key});

  @override
  ConsumerState<ManualSmsScreen> createState() => _ManualSmsScreenState();
}

class _ManualSmsScreenState extends ConsumerState<ManualSmsScreen> {
  final _receiver = TextEditingController(text: '+250788123456');
  final _body = TextEditingController();

  @override
  void dispose() {
    _receiver.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Manual SMS paste',
      subtitle:
          'Paste a receiver MOMO notification for secure ingestion and review.',
      children: [
        const InfoSecurityBanner(
          title: 'Restricted SMS handling',
          message:
              'Raw SMS is never public. Paste only receiver notifications you are authorized to monitor.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'Receiver MOMO number being validated',
                  helper:
                      'Used only for matching and authorization checks; never shown publicly.',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _body,
                minLines: 6,
                maxLines: 10,
                decoration: collectInputDecoration(
                  context,
                  label: 'Raw MOMO SMS',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Ingest SMS',
                icon: CollectIcons.sms,
                onPressed: () async {
                  final event = await ref
                      .read(collectRepositoryProvider.notifier)
                      .ingestManualSms(
                        _body.text,
                        receiverMomoNumber: _receiver.text,
                      );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SMS parsed as ${event.allocationStatus}.'),
                    ),
                  );
                },
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
