import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_receipt_principal_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _root =
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-operations-enrollment-workflow-20261001/sql/attempt3';
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('$_root/observed-$name-v3.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
DateTime _at(Map<String, dynamic> row, String key) =>
    DateTime.parse(row[key] as String);
Map<String, dynamic> _metadata() {
  final input = _fixture('enroll-input');
  return {
    'contract_version': 2,
    'scope': 'rw_receipt_operations',
    'public_key_spki_base64': input['public_key_spki_base64'],
    'key_sha256': input['key_sha256'],
  };
}

AdminReceiptPrincipalIntent _intent(String action) {
  final receipt = _fixture(action),
      created = _at(
        receipt,
        'request_expires_at',
      ).subtract(const Duration(seconds: 90));
  if (action == 'enroll') {
    return AdminReceiptPrincipalIntent.enroll(
      requestId: receipt['request_id'] as String,
      createdAt: created,
      requestExpiresAt: _at(receipt, 'request_expires_at'),
      identityExpiresAt: _at(receipt, 'identity_expires_at'),
      publicKey: AdminReceiptPrincipalPublicKey.parse(_metadata()),
    );
  }
  if (action == 'activate') {
    return AdminReceiptPrincipalIntent.activate(
      requestId: receipt['request_id'] as String,
      createdAt: created,
      requestExpiresAt: _at(receipt, 'request_expires_at'),
      identityExpiresAt: _at(receipt, 'identity_expires_at'),
      principalId: receipt['principal_id'] as String,
      keySha256: receipt['key_sha256'] as String,
    );
  }
  return _revoke(receipt);
}

AdminReceiptPrincipalIntent _revoke(Map<String, dynamic> receipt) =>
    AdminReceiptPrincipalIntent.revoke(
      requestId: receipt['request_id'] as String,
      createdAt: _at(
        receipt,
        'request_expires_at',
      ).subtract(const Duration(seconds: 90)),
      requestExpiresAt: _at(receipt, 'request_expires_at'),
      identityExpiresAt: _at(receipt, 'identity_expires_at'),
      principalId: receipt['principal_id'] as String,
      keySha256: receipt['key_sha256'] as String,
      reason: _fixture('revoke-input')['reason'] as String,
    );
List<Map<String, dynamic>> _pages() =>
    (jsonDecode(
              File('$_root/observed-identity-pages-v3.json').readAsStringSync(),
            )
            as List)
        .cast<Map<String, dynamic>>();
const _other = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

void main() {
  test(
    'public text accepts bounded flat metadata and normalized JSON escapes',
    () {
      final encoded = jsonEncode(_metadata());
      final key = AdminReceiptPrincipalPublicKey.parseText(encoded);
      expect(key.keySha256, _metadata()['key_sha256']);
      final escaped = encoded
          .replaceAll('"scope"', r'"\u0073cope"')
          .replaceAll('/', r'\/');
      expect(
        AdminReceiptPrincipalPublicKey.parseText(escaped).spkiBase64,
        key.spkiBase64,
      );
      final boundary = '${' ' * (2048 - utf8.encode(encoded).length)}$encoded';
      expect(
        AdminReceiptPrincipalPublicKey.parseText(boundary).keySha256,
        key.keySha256,
      );
      expect(
        () => AdminReceiptPrincipalPublicKey.parseText(' $boundary'),
        throwsFormatException,
      );
    },
  );
  test(
    'public text rejects duplicate decoded keys nesting private fields and non-JSON forms',
    () {
      final encoded = jsonEncode(_metadata());
      for (final text in [
        encoded.replaceFirst('{', '{"scope":"rw_receipt_operations",'),
        encoded.replaceFirst('{', r'{"\u0073cope":"rw_receipt_operations",'),
        encoded.replaceFirst('{', '{"private_key":"PRIVATE_CANARY",'),
        encoded.replaceFirst(
          '"scope":"rw_receipt_operations"',
          '"scope":{"value":"rw_receipt_operations"}',
        ),
        encoded.replaceFirst(
          '"scope":"rw_receipt_operations"',
          '"scope":["rw_receipt_operations"]',
        ),
        encoded.replaceFirst('"contract_version":2', '"contract_version":2.0'),
        encoded.replaceFirst('"contract_version":2', '"contract_version":"2"'),
        '$encoded{}',
        '$encoded trailing',
        encoded.replaceFirst('}', ',}'),
        '\u00a0$encoded',
        '',
        '[]',
        '{}',
        encoded.replaceFirst('"scope"', r'"\x73cope"'),
      ]) {
        expect(
          () => AdminReceiptPrincipalPublicKey.parseText(text),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'actual CLI public metadata validates canonical P256 and fingerprint',
    () {
      final raw = _metadata(), key = AdminReceiptPrincipalPublicKey.parse(raw);
      expect(key.spkiBase64, raw['public_key_spki_base64']);
      expect(key.keySha256, raw['key_sha256']);
    },
  );
  test(
    'public metadata refuses private material unsupported scope and altered bytes',
    () {
      final raw = _metadata();
      for (final patch in [
        {'contract_version': 3},
        {'contract_version': 2.0},
        {'scope': 'rw_receipt_shadow'},
        {'key_sha256': 'A' * 64},
        {'key_sha256': 'a' * 64},
        {'public_key_spki_base64': '${raw['public_key_spki_base64']}\n'},
        {'private_key': 'PRIVATE_CANARY'},
        {'authorization': 'PRIVATE_CANARY'},
      ]) {
        expect(
          () => AdminReceiptPrincipalPublicKey.parse({...raw, ...patch}),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptPrincipalPublicKey.parse({...raw}..remove(key)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'correct canonical DER and digest still refuse an off-curve public point',
    () {
      final raw = _metadata(),
          bytes = base64Decode(raw['public_key_spki_base64'] as String);
      bytes.fillRange(27, 91, 0);
      expect(
        () => AdminReceiptPrincipalPublicKey.parse({
          ...raw,
          'public_key_spki_base64': base64Encode(bytes),
          'key_sha256': sha256.convert(bytes).toString(),
        }),
        throwsFormatException,
      );
      bytes[0] = 0x31;
      expect(
        () => AdminReceiptPrincipalPublicKey.parse({
          ...raw,
          'public_key_spki_base64': base64Encode(bytes),
          'key_sha256': sha256.convert(bytes).toString(),
        }),
        throwsFormatException,
      );
    },
  );
  for (final action in ['enroll', 'activate', 'revoke']) {
    test(
      '$action bookmark roundtrip retains only immutable original metadata',
      () {
        final intent = _intent(action),
            binding = AdminReceiptPrincipalBinding.fromIntent(intent),
            encoded = binding.toJson();
        expect(encoded.keys.toSet(), {
          'action',
          'request_id',
          'principal_id',
          'key_sha256',
          'identity_expires_at',
          'created_at',
          'request_expires_at',
          'reason_sha256',
        });
        final restored = AdminReceiptPrincipalBinding.parse(
          jsonDecode(jsonEncode(encoded)),
        );
        expect(restored.toJson(), encoded);
        expect(restored, isNot(isA<AdminReceiptPrincipalIntent>()));
        expect(
          jsonEncode(
            encoded,
          ).contains(_metadata()['public_key_spki_base64'] as String),
          isFalse,
        );
        expect(
          jsonEncode(
            encoded,
          ).contains(_fixture('revoke-input')['reason'] as String),
          isFalse,
        );
        expect(() => encoded['request_id'] = _other, throwsUnsupportedError);
        expect(restored.lookupParameters, {'p_request_id': intent.requestId});
      },
    );
    test('$action intent emits exactly the existing v3 RPC parameters', () {
      final intent = _intent(action), receipt = _fixture(action);
      expect(intent.rpcName, 'admin_${action}_receipt_operations_identity_v3');
      final parameters = <String, dynamic>{
        'p_request_id': receipt['request_id'],
        'p_request_expires_at': receipt['request_expires_at'],
      };
      if (action == 'enroll') {
        parameters.addAll({
          'p_public_key_spki_base64': _metadata()['public_key_spki_base64'],
          'p_key_sha256': receipt['key_sha256'],
          'p_identity_expires_at': receipt['identity_expires_at'],
        });
      } else {
        parameters.addAll({
          'p_principal_id': receipt['principal_id'],
          'p_expected_key_sha256': receipt['key_sha256'],
        });
      }
      if (action == 'revoke') {
        parameters['p_reason'] = _fixture('revoke-input')['reason'];
      }
      expect(intent.parameters, parameters);
      expect(() => intent.parameters.clear(), throwsUnsupportedError);
      expect(intent.canSubmitAt(intent.createdAt), isTrue);
      expect(intent.canSubmitAt(intent.requestExpiresAt), isFalse);
    });
  }
  test(
    'bookmarks refuse malformed bindings private fields and incompatible actions',
    () {
      final raw = AdminReceiptPrincipalBinding.fromIntent(
        _intent('enroll'),
      ).toJson();
      for (final patch in [
        {'action': 'configure'},
        {'principal_id': _other},
        {'reason_sha256': 'a' * 64},
        {'request_id': 'PRIVATE_CANARY'},
        {'key_sha256': 'A' * 64},
        {'request_expires_at': raw['created_at']},
        {'identity_expires_at': raw['created_at']},
        {'created_at': '2026-02-30T00:00:00.000000Z'},
        {'reason': 'PRIVATE_CANARY'},
        {'public_key_spki_base64': _metadata()['public_key_spki_base64']},
      ]) {
        expect(
          () => AdminReceiptPrincipalBinding.parse({...raw, ...patch}),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptPrincipalBinding.parse({...raw}..remove(key)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'new intents enforce 120-second original windows and enrollment lifetime',
    () {
      final source = _intent('enroll');
      for (final delta in [Duration.zero, const Duration(seconds: 121)]) {
        expect(
          () => AdminReceiptPrincipalIntent.enroll(
            requestId: source.requestId,
            createdAt: source.createdAt,
            requestExpiresAt: source.createdAt.add(delta),
            identityExpiresAt: source.identityExpiresAt,
            publicKey: source.publicKey!,
          ),
          throwsFormatException,
        );
      }
      for (final delta in [
        const Duration(minutes: 9),
        const Duration(days: 31),
      ]) {
        expect(
          () => AdminReceiptPrincipalIntent.enroll(
            requestId: source.requestId,
            createdAt: source.createdAt,
            requestExpiresAt: source.requestExpiresAt,
            identityExpiresAt: source.createdAt.add(delta),
            publicKey: source.publicKey!,
          ),
          throwsFormatException,
        );
      }
      expect(
        source.canSubmitAt(
          source.createdAt.subtract(const Duration(seconds: 11)),
        ),
        isFalse,
      );
      final future = AdminReceiptPrincipalIntent.enroll(
        requestId: source.requestId,
        createdAt: source.createdAt,
        requestExpiresAt: source.createdAt.add(const Duration(seconds: 120)),
        identityExpiresAt: source.identityExpiresAt,
        publicKey: source.publicKey!,
      );
      expect(
        future.canSubmitAt(
          source.createdAt.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    },
  );
  test(
    'revocation reason is bounded control-free input with only its digest in binding',
    () {
      final source = _intent('revoke');
      for (final reason in [
        'short',
        ' owner reason',
        'owner reason ',
        'owner\nreason',
        'owner\u0000reason',
        'x' * 501,
      ]) {
        expect(
          () => AdminReceiptPrincipalIntent.revoke(
            requestId: source.requestId,
            createdAt: source.createdAt,
            requestExpiresAt: source.requestExpiresAt,
            identityExpiresAt: source.identityExpiresAt,
            principalId: source.principalId!,
            keySha256: source.keySha256,
            reason: reason,
          ),
          throwsFormatException,
        );
      }
      expect(source.reasonSha256, _fixture('revoke-input')['reason_sha256']);
    },
  );
  test(
    'expired pending and expired active identities remain revocable but activation refuses expiry',
    () {
      for (final name in ['revoke-expired-active', 'revoke-expired-pending']) {
        final intent = _revoke(_fixture(name));
        expect(intent.canSubmitAt(intent.createdAt), isTrue);
        expect(intent.identityExpiresAt.isBefore(intent.createdAt), isTrue);
        expect(
          () => AdminReceiptPrincipalIntent.activate(
            requestId: intent.requestId,
            createdAt: intent.createdAt,
            requestExpiresAt: intent.requestExpiresAt,
            identityExpiresAt: intent.identityExpiresAt,
            principalId: intent.principalId!,
            keySha256: intent.keySha256,
          ),
          throwsFormatException,
        );
      }
    },
  );
  final pages = _pages();
  for (var index = 0; index < pages.length; index++) {
    test(
      'actual SQL directory page $index binds paired descending keyset and next cursor',
      () {
        final before = index == 0
            ? null
            : AdminReceiptPrincipalCursor.parse(
                pages[index - 1]['next_cursor'],
              );
        final directory = AdminReceiptPrincipalDirectory.parse(
          pages[index],
          query: AdminReceiptPrincipalDirectoryQuery(limit: 2, before: before),
        );
        expect(
          directory.rows.map((row) => row.principalId),
          (pages[index]['rows'] as List).map(
            (row) => (row as Map)['principal_id'],
          ),
        );
        expect(directory.nextCursor?.toJson(), pages[index]['next_cursor']);
        expect(directory.isFresh(directory.checkedAt), isTrue);
        expect(directory.isFresh(directory.validUntil), isFalse);
        expect(() => directory.rows.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'directory queries validate limits paired keys and immutable equality for provider families',
    () {
      const first = AdminReceiptPrincipalDirectoryQuery();
      expect(first.parameters, {
        'p_limit': 25,
        'p_before_created_at': null,
        'p_before_principal_id': null,
      });
      final cursor = AdminReceiptPrincipalCursor.parse(
        pages.first['next_cursor'],
      );
      final query = AdminReceiptPrincipalDirectoryQuery(
        limit: 2,
        before: cursor,
      );
      expect(query.parameters, {
        'p_limit': 2,
        'p_before_created_at': cursor.toJson()['created_at'],
        'p_before_principal_id': cursor.principalId,
      });
      final equal = AdminReceiptPrincipalDirectoryQuery(
        limit: 2,
        before: AdminReceiptPrincipalCursor.parse(cursor.toJson()),
      );
      expect(query, equal);
      expect(query.hashCode, equal.hashCode);
      expect(() => query.parameters.clear(), throwsUnsupportedError);
      for (final limit in [0, 26]) {
        expect(
          () => AdminReceiptPrincipalDirectoryQuery(limit: limit).parameters,
          throwsFormatException,
        );
      }
      expect(
        () => AdminReceiptPrincipalCursor.parse({
          'created_at': cursor.toJson()['created_at'],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'directory refuses duplicate IDs order reversal extra rows and unbound continuation',
    () {
      final raw = pages.first;
      for (final kind in [
        'duplicate',
        'reverse',
        'oversize',
        'cursor',
        'partial_cursor',
      ]) {
        final changed = _copy(raw);
        if (kind == 'duplicate') {
          changed['rows'][1]['principal_id'] =
              changed['rows'][0]['principal_id'];
        }
        if (kind == 'reverse') {
          changed['rows'] = (changed['rows'] as List).reversed.toList();
        }
        if (kind == 'oversize') {
          (changed['rows'] as List).add(_copy(raw)['rows'][0]);
        }
        if (kind == 'cursor') {
          changed['next_cursor']['principal_id'] = _other;
        }
        if (kind == 'partial_cursor') {
          (changed['next_cursor'] as Map).remove('created_at');
        }
        expect(
          () => AdminReceiptPrincipalDirectory.parse(
            changed,
            query: const AdminReceiptPrincipalDirectoryQuery(limit: 2),
          ),
          throwsFormatException,
        );
      }
      final firstRow = (raw['rows'] as List).first as Map;
      expect(
        () => AdminReceiptPrincipalDirectory.parse(
          raw,
          query: AdminReceiptPrincipalDirectoryQuery(
            limit: 2,
            before: AdminReceiptPrincipalCursor(
              createdAt: DateTime.parse(firstRow['created_at'] as String),
              principalId: firstRow['principal_id'] as String,
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'equal timestamp pages use strict UUID tie-breaking without offset guessing',
    () {
      final raw = _copy(pages.first);
      raw['rows'][0]['created_at'] = raw['rows'][1]['created_at'];
      final directory = AdminReceiptPrincipalDirectory.parse(
        raw,
        query: const AdminReceiptPrincipalDirectoryQuery(limit: 2),
      );
      expect(
        directory.rows.first.principalId.compareTo(
          directory.rows.last.principalId,
        ),
        greaterThan(0),
      );
      final reversed = _copy(raw);
      reversed['rows'] = (reversed['rows'] as List).reversed.toList();
      reversed['next_cursor'] = {
        'created_at': reversed['rows'][1]['created_at'],
        'principal_id': reversed['rows'][1]['principal_id'],
      };
      expect(
        () => AdminReceiptPrincipalDirectory.parse(
          reversed,
          query: const AdminReceiptPrincipalDirectoryQuery(limit: 2),
        ),
        throwsFormatException,
      );
    },
  );
  for (final name in [
    'identity-active',
    'identity-expired-active',
    'identity-revoked',
  ]) {
    test(
      'actual $name observation retains lifecycle independently of expiry',
      () {
        final raw = _fixture(name),
            principal = (raw['identity'] as Map)['principal_id'] as String;
        final view = AdminReceiptPrincipalObservation.parse(
          raw,
          principalId: principal,
        );
        expect(view.found, isTrue);
        expect(view.identity!.state.name, (raw['identity'] as Map)['state']);
        expect(view.identity!.state.label, isNotEmpty);
        expect(
          view.identity!.isExpired(view.checkedAt),
          name == 'identity-expired-active',
        );
        expect(view.isFresh(view.checkedAt), isTrue);
        expect(view.isFresh(view.validUntil), isFalse);
      },
    );
  }
  test(
    'current missing identity never invents a principal and binds queried IDs',
    () {
      final raw = _fixture('identity-active'),
          principal = (raw['identity'] as Map)['principal_id'] as String;
      expect(
        () => AdminReceiptPrincipalObservation.parse(raw, principalId: _other),
        throwsFormatException,
      );
      final missing = {...raw, 'found': false, 'identity': null};
      final view = AdminReceiptPrincipalObservation.parse(
        missing,
        principalId: principal,
      );
      expect(view.found, isFalse);
      expect(view.identity, isNull);
      expect(
        () => AdminReceiptPrincipalObservation.parse({
          ...missing,
          'found': true,
        }, principalId: principal),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptPrincipalObservation.parse({
          ...raw,
          'found': false,
        }, principalId: principal),
        throwsFormatException,
      );
    },
  );
  test(
    'identity lifecycle and observed timestamps reject incompatible fabricated states',
    () {
      final raw = _fixture('identity-active'),
          principal = (raw['identity'] as Map)['principal_id'] as String;
      for (final patch in [
        {'state': 'expired'},
        {'state': 'pending'},
        {'state': 'revoked'},
        {'activated_at': null},
        {'revoked_at': raw['checked_at']},
        {'scope': 'rw_receipt_shadow'},
        {'created_at': raw['sample_valid_until']},
        {'activated_at': raw['sample_valid_until']},
        {'expires_at': (raw['identity'] as Map)['created_at']},
        {'key_sha256': 'A' * 64},
      ]) {
        final changed = _copy(raw);
        (changed['identity'] as Map).addAll(patch);
        expect(
          () => AdminReceiptPrincipalObservation.parse(
            changed,
            principalId: principal,
          ),
          throwsFormatException,
        );
      }
      final expiredPending = AdminReceiptPrincipalDirectory.parse(
        pages.last,
        query: const AdminReceiptPrincipalDirectoryQuery(limit: 2),
      ).rows.last;
      expect(expiredPending.state, AdminReceiptPrincipalState.pending);
      expect(expiredPending.isExpired(_at(pages.last, 'checked_at')), isTrue);
    },
  );
  test(
    'exact read schemas reject each missing key and private/freeform additions',
    () {
      final raw = _fixture('identity-active'),
          principal = (raw['identity'] as Map)['principal_id'] as String;
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptPrincipalObservation.parse(
            {...raw}..remove(key),
            principalId: principal,
          ),
          throwsFormatException,
        );
      }
      for (final key in (raw['identity'] as Map).keys) {
        final changed = _copy(raw);
        (changed['identity'] as Map).remove(key);
        expect(
          () => AdminReceiptPrincipalObservation.parse(
            changed,
            principalId: principal,
          ),
          throwsFormatException,
        );
      }
      for (final key in [
        'private_key',
        'phone',
        'authorization',
        'reason',
        'role',
        'error_message',
      ]) {
        expect(
          () => AdminReceiptPrincipalObservation.parse({
            ...raw,
            key: 'PRIVATE_CANARY',
          }, principalId: principal),
          throwsFormatException,
        );
        final changed = _copy(raw);
        changed['identity'][key] = 'PRIVATE_CANARY';
        expect(
          () => AdminReceiptPrincipalObservation.parse(
            changed,
            principalId: principal,
          ),
          throwsFormatException,
        );
        expect(
          () => AdminReceiptPrincipalDirectory.parse({
            ...pages.first,
            key: 'PRIVATE_CANARY',
          }, query: const AdminReceiptPrincipalDirectoryQuery(limit: 2)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'v3 read freshness matches sixty-second TTL and ten-second future-clock tolerance',
    () {
      final raw = _fixture('identity-active'),
          principal = (raw['identity'] as Map)['principal_id'] as String;
      final view = AdminReceiptPrincipalObservation.parse(
        raw,
        principalId: principal,
      );
      expect(
        view.isFresh(view.checkedAt.subtract(const Duration(seconds: 10))),
        isTrue,
      );
      expect(
        view.isFresh(view.checkedAt.subtract(const Duration(seconds: 11))),
        isFalse,
      );
      for (final patch in [
        {'contract_version': 2},
        {'contract_version': 3.0},
        {'sample_valid_until': raw['checked_at']},
        {'checked_at': '2026-10-01T13:03:07Z'},
      ]) {
        expect(
          () => AdminReceiptPrincipalObservation.parse({
            ...raw,
            ...patch,
          }, principalId: principal),
          throwsFormatException,
        );
      }
    },
  );
  for (final name in [
    'enroll',
    'activate',
    'revoke',
    'revoke-expired-active',
    'revoke-expired-pending',
  ]) {
    test(
      'actual $name immutable receipt binds original action key principal and deadlines',
      () {
        final raw = _fixture(name),
            binding = name.startsWith('revoke-') ? _revoke(raw) : _intent(name);
        final receipt = AdminReceiptPrincipalReceipt.parse(
          raw,
          binding: binding,
        );
        expect(receipt.action.name, raw['action']);
        expect(receipt.stateAtAction.name, raw['state_at_action']);
        expect(receipt.requestId, binding.requestId);
        expect(receipt.identityExpiresAt, binding.identityExpiresAt);
        expect(receipt.requestExpiresAt, binding.requestExpiresAt);
        expect(receipt.reasonSha256, raw['reason_sha256']);
        expect(
          AdminReceiptPrincipalReceipt.parse(
            raw,
            binding: AdminReceiptPrincipalBinding.parse(binding.toJson()),
          ).principalId,
          receipt.principalId,
        );
      },
    );
  }
  test(
    'receipt original binding cannot be changed by unsupported state key deadline or reason',
    () {
      final raw = _fixture('revoke'), binding = _intent('revoke');
      for (final patch in [
        {'contract_version': 2},
        {'request_id': _other},
        {'principal_id': _other},
        {'action': 'activate'},
        {'key_sha256': 'a' * 64},
        {'state_at_action': 'active'},
        {'scope': 'rw_receipt_shadow'},
        {'identity_expires_at': raw['request_expires_at']},
        {'request_expires_at': raw['identity_expires_at']},
        {'recorded_at': raw['request_expires_at']},
        {'reason_sha256': 'a' * 64},
        {'reason': 'PRIVATE_CANARY'},
      ]) {
        expect(
          () => AdminReceiptPrincipalReceipt.parse({
            ...raw,
            ...patch,
          }, binding: binding),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptPrincipalReceipt.parse(
            {...raw}..remove(key),
            binding: binding,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AdminReceiptPrincipalReceipt.parse(
          _fixture('activate'),
          binding: _intent('enroll'),
        ),
        throwsFormatException,
      );
    },
  );
  for (final action in ['enroll', 'activate', 'revoke']) {
    test(
      'actual $action original lookup survives metadata-only bookmark restoration',
      () {
        final raw = _fixture('$action-lookup'),
            binding = AdminReceiptPrincipalBinding.parse(
              _intent(action).toJson(),
            );
        final lookup = AdminReceiptPrincipalLookup.parse(raw, binding: binding);
        expect(lookup.status, 'recorded');
        expect(lookup.action, binding.action);
        expect(lookup.receipt!.requestId, binding.requestId);
        expect(lookup.isFresh(lookup.checkedAt), isTrue);
        expect(lookup.provesExpiredAbsence(lookup.checkedAt), isFalse);
      },
    );
  }
  for (final state in ['not-recorded', 'in-progress']) {
    test(
      'actual $state lookup retains uncertainty before its original deadline',
      () {
        final raw = _fixture(state), checked = _at(raw, 'checked_at');
        // Explicit retained-original bookmark fixture; the SQL read remains actual.
        final binding = AdminReceiptPrincipalBinding.parse({
          ..._intent('enroll').toJson(),
          'request_id': raw['request_id'],
          'created_at': operationsUtc(checked),
          'request_expires_at': operationsUtc(
            checked.add(const Duration(seconds: 90)),
          ),
        });
        final lookup = AdminReceiptPrincipalLookup.parse(raw, binding: binding);
        expect(lookup.status, raw['status']);
        expect(lookup.receipt, isNull);
        expect(lookup.action, isNull);
        expect(lookup.requestExpiresAt, isNull);
        expect(lookup.provesExpiredAbsence(checked), isFalse);
      },
    );
  }
  test(
    'lookup refuses wrong original cross-action unbound receipt and private output',
    () {
      final raw = _fixture('revoke-lookup'), binding = _intent('revoke');
      for (final patch in [
        {'request_id': _other},
        {'action': 'activate'},
        {'status': 'sent'},
        {'status': 'not_recorded'},
        {'request_expires_at': raw['checked_at']},
        {'receipt': null},
        {'reason': 'PRIVATE_CANARY'},
        {'checked_at': operationsUtc(binding.createdAt)},
      ]) {
        expect(
          () => AdminReceiptPrincipalLookup.parse({
            ...raw,
            ...patch,
          }, binding: binding),
          throwsFormatException,
        );
      }
      final changed = _copy(raw);
      changed['receipt']['principal_id'] = _other;
      expect(
        () => AdminReceiptPrincipalLookup.parse(changed, binding: binding),
        throwsFormatException,
      );
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptPrincipalLookup.parse(
            {...raw}..remove(key),
            binding: binding,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'only fresh server absence after the retained enforced deadline closes an unknown original',
    () {
      final raw = _fixture('not-recorded'), checked = _at(raw, 'checked_at');
      final metadata = {
        ..._intent('enroll').toJson(),
        'request_id': raw['request_id'],
        'created_at': operationsUtc(
          checked.subtract(const Duration(seconds: 120)),
        ),
        'request_expires_at': operationsUtc(
          checked.subtract(const Duration(seconds: 1)),
        ),
      };
      final binding = AdminReceiptPrincipalBinding.parse(metadata);
      final lookup = AdminReceiptPrincipalLookup.parse(raw, binding: binding);
      expect(lookup.provesExpiredAbsence(checked), isTrue);
      expect(
        lookup.provesExpiredAbsence(
          checked.subtract(const Duration(seconds: 2)),
        ),
        isFalse,
      );
      expect(lookup.provesExpiredAbsence(lookup.validUntil), isFalse);
      final inProgress = {...raw, 'status': 'in_progress'};
      expect(
        AdminReceiptPrincipalLookup.parse(
          inProgress,
          binding: binding,
        ).provesExpiredAbsence(checked),
        isFalse,
      );
      final futureDeadline = AdminReceiptPrincipalBinding.parse({
        ...metadata,
        'created_at': operationsUtc(
          checked.subtract(const Duration(seconds: 30)),
        ),
        'request_expires_at': operationsUtc(
          checked.add(const Duration(seconds: 1)),
        ),
      });
      expect(
        AdminReceiptPrincipalLookup.parse(
          raw,
          binding: futureDeadline,
        ).provesExpiredAbsence(checked.add(const Duration(seconds: 2))),
        isFalse,
      );
    },
  );
}
