import 'package:collect_app/admin/core/admin_action_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

const a = '99430000-0000-4000-8000-000000000001';
const b = '99430000-0000-4000-8000-000000000002';
const auditReason = 'Synthetic local evidence review';
List<(String, Map<String, dynamic>, Map<String, dynamic>)>
adminActionContractFixtures() =>
    <(String, Map<String, dynamic>, Map<String, dynamic>)>[
      (
        'admin_retry_notification',
        {'p_event_id': a, 'p_reason': auditReason},
        {'ok': true, 'status': 'queued', 'delivery_count': 1},
      ),
      (
        'admin_create_platform_public_group',
        {
          'p_title': 'Synthetic reviewed group',
          'p_description': 'Synthetic local fixture',
          'p_collection_type': 'ikimina',
          'p_category_subtype': 'community',
          'p_purpose_label': 'Synthetic savings purpose',
          'p_receiver_label': 'Synthetic official payee',
          'p_momo_code': '123456',
          'p_network': 'mtn_momo',
          'p_reason': auditReason,
        },
        {
          'ok': true,
          'collection_id': a,
          'payee_id': b,
          'status': 'active',
          'visibility': 'public_approved',
          'route_immutable': true,
        },
      ),
      (
        'admin_set_group_active',
        {'p_collection_id': a, 'p_active': true, 'p_reason': auditReason},
        {
          'ok': true,
          'collection_id': a,
          'active': true,
          'status': 'active',
          'visibility': 'private',
        },
      ),
      (
        'admin_set_group_active',
        {'p_collection_id': a, 'p_active': false, 'p_reason': auditReason},
        {
          'ok': true,
          'collection_id': a,
          'active': false,
          'status': 'inactive',
          'visibility': 'archived',
        },
      ),
      (
        'admin_update_platform_public_group_metadata',
        {'p_collection_id': a, 'p_reason': auditReason},
        {
          'ok': true,
          'collection_id': a,
          'receiver_id': b,
          'public_status': 'public_approved',
          'visibility': 'archived',
          'status': 'inactive',
        },
      ),
      (
        'admin_update_collection_support_status',
        {'p_collection_id': a, 'p_status': 'archived', 'p_reason': auditReason},
        {'ok': true, 'status': 'archived'},
      ),
      (
        'admin_create_collect_payee',
        {
          'p_collection_id': b,
          'p_label': 'Synthetic official payee',
          'p_momo_code': '123456',
          'p_network': 'mtn_momo',
          'p_reason': auditReason,
        },
        {
          'ok': true,
          'payee_id': a,
          'status': 'active',
          'route_immutable': true,
        },
      ),
      (
        'admin_update_collect_payee',
        {'p_payee_id': a, 'p_label': ' New name ', 'p_reason': auditReason},
        {
          'ok': true,
          'payee_id': a,
          'label': 'New name',
          'route_immutable': true,
        },
      ),
      (
        'admin_set_collect_payee_status',
        {'p_payee_id': a, 'p_active': false, 'p_reason': auditReason},
        {
          'ok': true,
          'payee_id': a,
          'status': 'inactive',
          'route_immutable': true,
        },
      ),
      (
        'admin_set_feature_flag_v2',
        {
          'p_key': 'flag',
          'p_enabled': false,
          'p_expected_revision': 1,
          'p_reason': auditReason,
        },
        {
          'contract_version': 2,
          'ok': true,
          'previous_revision': 1,
          'revision': 2,
          'changed': true,
          'key': 'flag',
          'enabled': false,
          'updated_at': '2026-09-30T00:00:00Z',
        },
      ),
      (
        'admin_record_operator_note',
        {
          'p_entity_type': 'collection',
          'p_entity_id': a,
          'p_body': auditReason,
        },
        {'ok': true, 'note_id': a},
      ),
      (
        'admin_reparse_payment_event',
        {'p_event_id': a, 'p_reason': auditReason},
        {'ok': true, 'message': 'Reparse queued for review'},
      ),
      (
        'admin_reveal_raw_sms',
        {'p_sms_id': a, 'p_reason': 'Internal audit evidence'},
        {'ok': true, 'message': 'Synthetic protected receipt'},
      ),
      (
        'admin_manual_allocate_payment',
        {
          'p_payment_id': a,
          'p_collection_id': b,
          'p_receiver_id': b,
          'p_reason': auditReason,
        },
        {'status': 'allocated', 'payment_id': a},
      ),
      (
        'admin_approve_whatsapp',
        {
          'p_user_id': a,
          'p_reason': auditReason,
          'p_whatsapp_phone': '+250788943001',
        },
        {'ok': true, 'status': 'approved', 'user_id': a},
      ),
      (
        'admin_revoke_whatsapp_approval',
        {'p_user_id': a, 'p_reason': auditReason},
        {'ok': true, 'status': 'revoked', 'user_id': a},
      ),
      (
        'admin_set_user_access',
        {'p_user_id': a, 'p_active': false, 'p_reason': auditReason},
        {'ok': true, 'status': 'revoked'},
      ),
      (
        'admin_get_whatsapp_approval',
        {'p_user_id': a},
        {
          'user_id': a,
          'approved': true,
          'role_granted': false,
          'admin_access': false,
          'status': 'approved',
          'phone_masked': null,
          'approved_at': '2026-09-30T00:00:00Z',
          'expires_at': null,
          'access_status': 'approved',
        },
      ),
    ];

void main() {
  final cases = adminActionContractFixtures();
  for (var i = 0; i < cases.length; i++) {
    final (operation, request, receipt) = cases[i];
    test(
      'source SQL receipt contract $i accepts complete receipt: $operation',
      () {
        expect(
          () => validateAdminActionReceipt(operation, request, receipt),
          returnsNormally,
        );
      },
    );
    test(
      'source SQL receipt contract $i rejects empty or missing fields: $operation',
      () {
        expect(
          () => validateAdminActionReceipt(operation, request, {}),
          throwsFormatException,
        );
        for (final key in receipt.keys) {
          final missing = Map<String, dynamic>.of(receipt)..remove(key);
          expect(
            () => validateAdminActionReceipt(operation, request, missing),
            throwsFormatException,
            reason: 'missing $key',
          );
        }
      },
    );
    if (receipt.containsKey('ok')) {
      test(
        'source SQL receipt contract $i rejects string and false success',
        () {
          for (final ok in [false, 'true', 1, null]) {
            expect(
              () => validateAdminActionReceipt(operation, request, {
                ...receipt,
                'ok': ok,
              }),
              throwsFormatException,
            );
          }
        },
      );
    }
    for (final field in ['collection_id', 'payee_id', 'user_id']) {
      if (request.containsKey('p_$field') && receipt.containsKey(field)) {
        test('$operation refuses wrong $field binding $i', () {
          expect(
            () => validateAdminActionReceipt(operation, request, {
              ...receipt,
              field: b,
            }),
            throwsFormatException,
          );
        });
      }
    }
  }
  test('active group cannot acknowledge archived visibility', () {
    expect(
      () => validateAdminActionReceipt(
        'admin_set_group_active',
        {'p_collection_id': a, 'p_active': true},
        {
          'ok': true,
          'collection_id': a,
          'active': true,
          'status': 'active',
          'visibility': 'archived',
        },
      ),
      throwsFormatException,
    );
  });
  test('unrecognized action cannot silently imply success', () {
    expect(
      () => validateAdminActionReceipt('admin_unreviewed_action', {}, {
        'ok': true,
      }),
      throwsFormatException,
    );
  });
}
