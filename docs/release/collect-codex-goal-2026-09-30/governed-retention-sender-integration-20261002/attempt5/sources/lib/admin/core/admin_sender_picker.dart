import 'package:flutter/material.dart';
import 'admin_gateway_contracts.dart';
import 'admin_gateway_models.dart';

/// Resolve a finite current gateway page without claiming absent IDs do not
/// exist. Reorders only the supplied allowlist; the existing v2 configure and
/// durable checkpoint remain the only mutation consumer.
class AdminSenderPicker extends StatelessWidget {
  const AdminSenderPicker({
    required this.deviceIds,
    required this.snapshot,
    required this.now,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final List<String> deviceIds;
  final AdminGatewaySnapshot? snapshot;
  final DateTime now;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;
  bool get evidenceReady =>
      snapshot != null &&
      snapshot!.isFresh(now) &&
      deviceIds.length <= 10 &&
      deviceIds.toSet().length == deviceIds.length &&
      deviceIds.every(
        (id) => snapshot!.rows.any(
          (d) =>
              d.identity.deviceId == id &&
              d.state == AdminGatewayDeviceState.active,
        ),
      );
  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final d in snapshot?.rows ?? <AdminGatewayDevice>[])
        d.identity.deviceId: d,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Android sender selection',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Text(
          'The first allowed device is the primary sender for a new run. Remaining devices are standbys; changing this draft uses the existing receipt operations policy request.',
        ),
        const SizedBox(height: 12),
        if (deviceIds.isEmpty)
          const Text('No gateway device is allowed by this policy.'),
        for (var i = 0; i < deviceIds.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i == 0 ? 'Primary sender' : 'Standby'} · ${deviceIds[i]}',
                ),
                if (byId[deviceIds[i]] case final d?) ...[
                  SelectableText('Installation ${d.identity.installationId}'),
                  Text(
                    'Enrollment state: ${d.state.name}. Health: ${d.health?.isFresh(now) == true ? 'current observation' : 'unavailable or stale'}.',
                  ),
                  if (d.health case final h?)
                    Text(
                      'SMS permission: ${h.smsPermission ? 'granted' : 'denied'}. Network: ${h.network}. Telephony: ${h.telephony}. Local pause: ${h.localPause ? 'on' : 'off'}.',
                    ),
                  SelectableText(
                    'Key ${d.identity.keySha256}\nSigning certificate ${d.identity.signingCertificateSha256}',
                  ),
                ] else
                  const Text(
                    'Unavailable in this finite gateway page. Keep this ID and refresh gateway evidence.',
                  ),
              ],
            ),
          ),
        if (deviceIds.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(deviceIds.join(',')),
            initialValue: deviceIds.first,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Primary allowed Android device',
            ),
            items: [
              // Pasted duplicate IDs remain in the draft and fail the evidence
              // gate. Dropdown values must still be unique to render safely.
              for (final id in deviceIds.toSet())
                DropdownMenuItem(value: id, child: Text(id)),
            ],
            onChanged: enabled && evidenceReady
                ? (id) {
                    if (id == null) return;
                    onChanged(
                      List.unmodifiable([
                        id,
                        ...deviceIds.where((value) => value != id),
                      ]),
                    );
                  }
                : null,
          ),
        if (!evidenceReady && deviceIds.isNotEmpty)
          const Text(
            'Current active evidence for every allowed device is required before changing this selection.',
          ),
        const SizedBox(height: 8),
        const Text(
          'Device enrollment and observed SIM selection do not prove ownership of a carrier line. Android uses the selected subscription; an arbitrary alphanumeric sender is unavailable.',
        ),
      ],
    );
  }
}
