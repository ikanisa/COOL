import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../profile/profile_edit_screen.dart';

class BankTransferSettingsScreen extends ConsumerWidget {
  const BankTransferSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    // Also guard direct embedding and profile changes during an in-flight read.
    // Never initialize a bank destination request for an ineligible profile.
    if (profile?.isDiaspora != true) return const ProfileEditScreen();
    return const _DiasporaBankTransferSettings();
  }
}

class _DiasporaBankTransferSettings extends ConsumerStatefulWidget {
  const _DiasporaBankTransferSettings();

  @override
  ConsumerState<_DiasporaBankTransferSettings> createState() =>
      _BankTransferSettingsScreenState();
}

class _BankTransferSettingsScreenState
    extends ConsumerState<_DiasporaBankTransferSettings> {
  late Future<BankTransferDestination> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _load();
  }

  Future<BankTransferDestination> _load() =>
      ref.read(collectRepositoryProvider.notifier).getBankTransferDestination();

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Bank transfer details',
    subtitle: 'Approved EUR bank-transfer beneficiary.',
    compact: true,
    onRefresh: () async {
      setState(() => _destination = _load());
      await _destination;
    },
    children: [
      FutureBuilder<BankTransferDestination>(
        future: _destination,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CollectScreenLoadingState(
              title: 'Loading beneficiary',
              message: 'Checking the approved bank-detail version.',
              icon: Icons.account_balance_rounded,
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const MinimalStatePanel(
              icon: Icons.cloud_off_rounded,
              title: 'Bank details are unavailable.',
              message: 'Refresh when you are back online.',
              tone: CollectStatusTone.warning,
            );
          }
          final destination = snapshot.data!;
          return Column(
            children: [
              if (destination.isPlaceholder || !destination.enabled)
                const InfoSecurityBanner(
                  title: 'Placeholder only — do not transfer',
                  message:
                      'These details are deliberately non-routable. Contributions remain disabled until real bank details pass independent maker-checker approval.',
                  tone: CollectStatusTone.warning,
                )
              else
                const InfoSecurityBanner(
                  title: 'Approved beneficiary',
                  message:
                      'Confirm these details in your banking app before every transfer. Collect never asks for banking credentials.',
                  tone: CollectStatusTone.privacy,
                ),
              CollectCard(
                emphasis: CollectCardEmphasis.normal,
                child: Column(
                  children: [
                    _CopySettingRow(
                      label: 'Name',
                      value: destination.beneficiaryName,
                    ),
                    _CopySettingRow(label: 'IBAN', value: destination.iban),
                    _CopySettingRow(label: 'BIC', value: destination.bic),
                    _CopySettingRow(label: 'Bank', value: destination.bankName),
                    _CopySettingRow(
                      label: 'Currency',
                      value: destination.currency,
                    ),
                    _CopySettingRow(
                      label: 'Scheme',
                      value: destination.supportsInstant
                          ? 'SEPA credit transfer · Instant supported'
                          : 'SEPA credit transfer',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _CopySettingRow extends StatelessWidget {
  const _CopySettingRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
        IconButton(
          tooltip: 'Copy $label',
          onPressed: value.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$label copied')));
                },
          icon: const Icon(CollectIcons.copy),
        ),
      ],
    ),
  );
}
