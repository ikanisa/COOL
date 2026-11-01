import 'cloudflare_admin_notification_operator_api.dart';
import 'cloudflare_admin_notification_operator_page.dart';
import 'cloudflare_admin_session.dart';

/// The browser never holds the OpenSMS application credential. The server
/// consumes a one-use original-start grant and reads its own immutable payload.
class CloudflareAdminAssistedSmsGateway
    implements
        NotificationOperatorAssistedSmsAdapter,
        NotificationOperatorAssistedSmsStatusAdapter {
  CloudflareAdminAssistedSmsGateway(this.session)
    : _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final ({int epoch, Object? key}) _fence;

  void _guard() {
    if (!session.mounted ||
        session.authorityFence != _fence ||
        session.logoutUnconfirmed ||
        session.user?.usesEmailVerification != true ||
        session.user?.permissions.contains('assisted_sms.manage') != true ||
        session.user?.hasRecentSensitiveVerification() != true) {
      throw StateError(
        'Reopen the original SMS review with current email verification.',
      );
    }
  }

  Future<NotificationOperatorAdapterObservation> _request(
    String action,
    String attemptId, {
    String? token,
  }) async {
    _guard();
    final response = await session.request(
      'notification-operator',
      authenticated: true,
      method: 'POST',
      body: {
        'action': action,
        'attempt_id': attemptId,
        'dispatch_token': ?token,
      },
    );
    _guard();
    final value = response['result'];
    const fields = {
      'contract_version',
      'scope',
      'delivery_confirmed',
      'provider_confirmation',
      'settlement_status',
      'may_send',
      'attempt_id',
      'gateway_state',
      'provider_accepted',
      'observation',
      'evidence_reference_sha256',
    };
    if (response.length != 2 ||
        response['ok'] != true ||
        value is! Map ||
        value.length != fields.length ||
        !fields.every(value.containsKey) ||
        value['contract_version'] != 1 ||
        value['scope'] != 'assisted_sms_gateway_observation' ||
        value['delivery_confirmed'] != false ||
        value['provider_confirmation'] != false ||
        value['settlement_status'] != 'not_asserted' ||
        value['may_send'] != false ||
        value['attempt_id'] != attemptId ||
        value['provider_accepted'] is! bool ||
        value['gateway_state'] is! String ||
        value['evidence_reference_sha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(value['evidence_reference_sha256'] as String)) {
      throw const FormatException(
        'The original gateway observation could not be verified.',
      );
    }
    final observation = switch (value['observation']) {
      null => null,
      'observed_sent' => NotificationOperatorObservation.observedSent,
      'failed_no_send' => NotificationOperatorObservation.failedNoSend,
      'uncertain' => NotificationOperatorObservation.uncertain,
      _ => throw const FormatException(
        'The gateway observation is unavailable.',
      ),
    };
    const pendingStates = {
      'accepted',
      'assigned',
      'phone_accepted',
      'queued',
      'handoff_started',
    };
    const sentStates = {'sent', 'delivered', 'delivery_unconfirmed'};
    const uncertainStates = {
      'failed',
      'partial',
      'outcome_unknown',
      'cancelled',
      'expired',
    };
    final state = value['gateway_state'] as String;
    if (value['provider_accepted'] == false
        ? state != 'unknown' || observation != null
        : !(pendingStates.contains(state) && observation == null ||
              sentStates.contains(state) &&
                  observation == NotificationOperatorObservation.observedSent ||
              uncertainStates.contains(state) &&
                  observation == NotificationOperatorObservation.uncertain)) {
      throw const FormatException(
        'The gateway state and observation disagree.',
      );
    }
    return NotificationOperatorAdapterObservation(
      observation: observation,
      evidenceReferenceSha256: value['evidence_reference_sha256'] as String,
      providerAccepted: value['provider_accepted'] as bool,
      gatewayState: value['gateway_state'] as String,
    );
  }

  @override
  Future<NotificationOperatorAdapterObservation> sendOnce(
    NotificationOperatorNativeSendContext context,
  ) {
    _guard();
    final payload = context.takeForImmediateDispatch();
    if (payload == null || payload.dispatchToken == null) {
      throw StateError('The original gateway sending grant is unavailable.');
    }
    return _request(
      'dispatch_gateway',
      payload.attemptId,
      token: payload.dispatchToken,
    );
  }

  @override
  Future<NotificationOperatorAdapterObservation> inspect(String attemptId) =>
      _request('inspect_gateway', attemptId);
}
