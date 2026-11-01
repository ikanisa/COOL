part of '../cloudflare_admin_notification_management_api_test.dart';

Map<String, dynamic> _batchReceipt(_Fixture f, {bool observed = true}) => {
  ..._marker('bounded_receipt_sms_materialization'),
  'request_id': _request,
  'observed': observed,
  'status': observed ? 'bounded_pass' : 'not_recorded',
  'may_be_in_flight': !observed,
  'planned_count': observed ? 0 : null,
  'items': <dynamic>[],
  'materialized_jobs': <dynamic>[],
  'materialized_count': 0,
  'blocked': null,
  'recorded_state_only': true,
  'may_send': false,
  'transport_started': false,
  'all_source_events_complete': false,
  if (observed) ...{
    'collection_id': _collection,
    'source_identity': 'immutable_contribution_entry_id',
    'originating_session_id': _canonicalSession,
    'public_session_id': _publicSession,
    'recorded_at': f.now.toIso8601String(),
    'has_more_observed': false,
  },
};

extension _NotificationMaterializationCases on _NotificationManagementApiSuite {
  void _registerNotificationMaterializationCases() {
    test(
      'bounded preparation requires current enabled policy and explicit owner confirmation',
      () async {
        final disabled = await fixture.api.getPolicy(_collection);
        expect(
          () => fixture.api.prepareMaterialization(
            expected: disabled,
            ownerConfirmation: true,
          ),
          throwsArgumentError,
        );
        fixture.policyEnabled = true;
        final policy = await fixture.api.getPolicy(_collection);
        expect(
          () => fixture.api.prepareMaterialization(
            expected: policy,
            ownerConfirmation: false,
          ),
          throwsArgumentError,
        );
        expect(
          () => fixture.api.prepareMaterialization(
            expected: policy,
            ownerConfirmation: true,
            limit: 11,
          ),
          throwsArgumentError,
        );
      },
    );
    test(
      'one bounded preparation preserves original request identity and never grants sending',
      () async {
        fixture.policyEnabled = true;
        final policy = await fixture.api.getPolicy(_collection);
        final operation = fixture.api.prepareMaterialization(
          expected: policy,
          ownerConfirmation: true,
          requestId: _request,
        );
        fixture.handler = (request) async =>
            _json({'ok': true, 'result': _batchReceipt(fixture)});
        final result = await fixture.api.materialize(operation);
        expect(result.resolved, true);
        expect(result.materializedCount, 0);
        final post = fixture.requests.last;
        expect(post.method, 'POST');
        expect(jsonDecode(post.body), {
          'request_id': _request,
          'collection_id': _collection,
          'limit': 5,
        });
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.materialize(operation),
          throwsA(anything),
        );
        expect(fixture.requests.length, count);
      },
    );
    test(
      'absent materialization remains unresolved and GET never reconstructs a command',
      () async {
        fixture.handler = (request) async => _json({
          'ok': true,
          'result': _batchReceipt(fixture, observed: false),
        });
        final receipt = await fixture.api.getMaterialization(_request);
        expect(receipt.observed, false);
        expect(receipt.mayBeInFlight, true);
        expect(receipt.resolved, false);
        expect(fixture.requests.single.method, 'GET');
      },
    );
    test(
      'materialization rejects transport claims, impossible counts and changed session',
      () async {
        fixture.policyEnabled = true;
        final policy = await fixture.api.getPolicy(_collection);
        final operation = fixture.api.prepareMaterialization(
          expected: policy,
          ownerConfirmation: true,
          requestId: _request,
        );
        for (final change in <void Function(Map<String, dynamic>)>[
          (r) => r['may_send'] = true,
          (r) => r['transport_started'] = true,
          (r) => r['materialized_count'] = 1,
          (r) => r['public_session_id'] = _other,
        ]) {
          final row = _batchReceipt(fixture);
          change(row);
          fixture.handler = (request) async =>
              _json({'ok': true, 'result': row});
          await expectLater(
            fixture.api.getMaterialization(
              _request,
              originalOperation: operation,
            ),
            throwsA(anything),
          );
        }
      },
    );
  }
}
