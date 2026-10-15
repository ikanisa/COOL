import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

const smsSourceKinds = {'member', 'receiver'};
const smsReceiptStatuses = {
  'pending',
  'parsed',
  'parse_failed',
  'needs_review',
  'rejected',
  'reviewed',
};
const smsExtractionStatuses = {'not_extracted', 'parsed', 'needs_review'};
const smsParserVersion = 'collect-admin-source-facts-v1';
final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _hash = RegExp(r'^[a-f0-9]{64}$');
final _phone = RegExp(r'^(?:\+?2507[2389][0-9]{7}|07[2389][0-9]{7})$');
Never _invalid() => throw const FormatException(
  'The SMS receipt response could not be verified.',
);
bool _id(Object? value) => value is String && _uuid.hasMatch(value);
bool _digest(Object? value) => value is String && _hash.hasMatch(value);
bool _int(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= 9007199254740991;
bool _text(Object? value, {int minimum = 1, int maximum = 1000}) =>
    value is String &&
    value.trim().length >= minimum &&
    value.length <= maximum &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
bool _nullable(Object? value, bool Function(Object?) check) =>
    value == null || check(value);
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : _invalid();
void _keys(Map<String, dynamic> data, Set<String> keys) {
  if (data.length != keys.length || !data.keys.every(keys.contains)) _invalid();
}

String _evidence(String kind) =>
    kind == 'member' ? 'member_submitted' : 'receiver_ingress_unverified';
bool _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse('${value}Z');
  return parsed != null && parsed.toIso8601String().substring(0, 19) == value;
}

bool _zone(Object? value) =>
    value is String &&
    RegExp(r'^[+-](?:0[0-9]|1[0-3]):[0-5][0-9]$|^[+-]14:00$').hasMatch(value);

class SmsReceiptPage<T> {
  const SmsReceiptPage(
    this.rows,
    this.total,
    this.limit,
    this.offset,
    this.nextOffset,
  );
  final List<T> rows;
  final int total, limit, offset;
  final int? nextOffset;
  static SmsReceiptPage<T> parse<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse,
  ) {
    _keys(data, {'rows', 'total', 'limit', 'offset', 'next_offset'});
    if (data['rows'] is! List ||
        !_int(data['total']) ||
        !_int(data['limit'], minimum: 1) ||
        (data['limit'] as int) > 100 ||
        !_int(data['offset']) ||
        (data['offset'] as int) > 2147483647 ||
        !_nullable(data['next_offset'], _int)) {
      _invalid();
    }
    final total = data['total'] as int,
        limit = data['limit'] as int,
        offset = data['offset'] as int;
    final rows = (data['rows'] as List)
        .map((value) => parse(_map(value)))
        .toList();
    if (rows.length != (total - offset).clamp(0, limit) ||
        data['next_offset'] !=
            (offset + rows.length < total ? offset + rows.length : null)) {
      _invalid();
    }
    return SmsReceiptPage(
      List.unmodifiable(rows),
      total,
      limit,
      offset,
      data['next_offset'] as int?,
    );
  }
}

/// Preserved source identity and nullable extracted facts, never provider finality.
class SmsReceiptSource {
  SmsReceiptSource._(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  String get kind => values['source_kind'] as String;
  String get identity => '$kind/$id';
  String get sourceHash => values['source_sha256'] as String;
  String get extractionStatus => values['extraction_status'] as String;
  factory SmsReceiptSource.parse(Map<String, dynamic> data) {
    _keys(data, {
      'source_kind',
      'id',
      'user_id',
      'payee_id',
      'source_sha256',
      'status',
      'version',
      'received_at',
      'created_at',
      'public_id',
      'display_name',
      'transaction_id',
      'evidence_level',
      'source_fact_id',
      'parser_version',
      'extraction_status',
      'source_body_sha256',
      'source_payload_sha256',
      'parsed_at',
      'payer_name',
      'payer_phone',
      'payer_masked_phone',
      'payer_last3',
      'payee_momo_number',
      'payee_momo_code',
      'momo_transaction_reference',
      'momo_timestamp_local',
      'momo_timezone_offset',
      'amount_rwf',
      'wallet_balance_rwf',
      'network',
      'direction',
      'is_payment',
      'transaction_reference',
      'duplicate_reference_count',
      'conflicting_reference_count',
      'provider_confirmation',
      'settlement_status',
      'timezone_known',
      'payer_last3_known',
      'source_content_reveal_required',
    });
    if (!smsSourceKinds.contains(data['source_kind']) ||
        !_id(data['id']) ||
        !_digest(data['source_sha256']) ||
        ![
          'version',
          'received_at',
          'created_at',
        ].every((key) => _int(data[key], minimum: 1)) ||
        ![
          'user_id',
          'payee_id',
          'transaction_id',
          'source_fact_id',
        ].every((key) => _nullable(data[key], _id)) ||
        !smsReceiptStatuses.contains(data['status']) ||
        !smsExtractionStatuses.contains(data['extraction_status']) ||
        !_nullable(
          data['public_id'],
          (v) => v is String && RegExp(r'^[0-9]{6}$').hasMatch(v),
        ) ||
        ![
          'display_name',
          'payer_name',
          'momo_transaction_reference',
        ].every((key) => _nullable(data[key], (v) => _text(v))) ||
        !['payer_phone', 'payee_momo_number'].every(
          (key) =>
              _nullable(data[key], (v) => v is String && _phone.hasMatch(v)),
        ) ||
        !_nullable(
          data['payer_masked_phone'],
          (v) => v is String && RegExp(r'^\*{3,}[0-9]{3}$').hasMatch(v),
        ) ||
        !_nullable(
          data['payer_last3'],
          (v) => v is String && RegExp(r'^[0-9]{3}$').hasMatch(v),
        ) ||
        !_nullable(
          data['payee_momo_code'],
          (v) => v is String && RegExp(r'^[0-9]{4,9}$').hasMatch(v),
        ) ||
        !_nullable(data['momo_timestamp_local'], _timestamp) ||
        !_nullable(data['momo_timezone_offset'], _zone) ||
        !_nullable(data['amount_rwf'], (v) => _int(v, minimum: 1)) ||
        !_nullable(data['wallet_balance_rwf'], _int) ||
        !_nullable(
          data['network'],
          (v) => {'mtn_momo', 'airtel_money'}.contains(v),
        ) ||
        !_nullable(
          data['direction'],
          (v) => {'incoming', 'outgoing'}.contains(v),
        ) ||
        !_nullable(data['is_payment'], (v) => v == 0 || v == 1) ||
        !_nullable(
          data['transaction_reference'],
          (v) => v is String && RegExp(r'^[0-9]{18}$').hasMatch(v),
        ) ||
        ![
          'duplicate_reference_count',
          'conflicting_reference_count',
        ].every((key) => _int(data[key])) ||
        (data['conflicting_reference_count'] as int) >
            (data['duplicate_reference_count'] as int) ||
        data['provider_confirmation'] != false ||
        data['settlement_status'] != 'not_asserted' ||
        data['source_content_reveal_required'] != true ||
        data['evidence_level'] != _evidence(data['source_kind'] as String) ||
        data['timezone_known'] != (data['momo_timezone_offset'] != null) ||
        data['payer_last3_known'] != (data['payer_last3'] != null)) {
      _invalid();
    }
    final member = data['source_kind'] == 'member';
    if (member
        ? !_id(data['user_id']) ||
              data['payee_id'] != null ||
              !{'needs_review', 'rejected', 'reviewed'}.contains(data['status'])
        : !_id(data['payee_id']) ||
              data['user_id'] != null ||
              data['public_id'] != null ||
              data['version'] != 1 ||
              !{
                'pending',
                'parsed',
                'parse_failed',
                'needs_review',
              }.contains(data['status'])) {
      _invalid();
    }
    final full = data['payer_phone'] as String?,
        masked = data['payer_masked_phone'] as String?,
        last3 = data['payer_last3'];
    final actual = full ?? masked;
    if (full != null && masked != null ||
        last3 != (actual?.substring(actual.length - 3)) ||
        data['momo_timezone_offset'] != null &&
            data['momo_timestamp_local'] == null) {
      _invalid();
    }
    const factKeys = {
      'source_fact_id',
      'parser_version',
      'source_body_sha256',
      'source_payload_sha256',
      'parsed_at',
      'payer_name',
      'payer_phone',
      'payer_masked_phone',
      'payer_last3',
      'payee_momo_number',
      'payee_momo_code',
      'momo_transaction_reference',
      'momo_timestamp_local',
      'momo_timezone_offset',
      'amount_rwf',
      'wallet_balance_rwf',
      'network',
      'direction',
      'is_payment',
    };
    if (data['extraction_status'] == 'not_extracted') {
      if (factKeys.any((key) => data[key] != null) ||
          data['duplicate_reference_count'] != 0 ||
          data['conflicting_reference_count'] != 0) {
        _invalid();
      }
    } else {
      if (!_id(data['source_fact_id']) ||
          data['parser_version'] != smsParserVersion ||
          !_digest(data['source_body_sha256']) ||
          !_digest(data['source_payload_sha256']) ||
          !_int(data['parsed_at'], minimum: 1) ||
          data['is_payment'] == null ||
          (member
                  ? data['source_body_sha256']
                  : data['source_payload_sha256']) !=
              data['source_sha256'] ||
          data['is_payment'] !=
              (data['direction'] != null &&
                      data['amount_rwf'] != null &&
                      data['network'] != null
                  ? 1
                  : 0) ||
          data['extraction_status'] !=
              (data['is_payment'] == 1 &&
                      data['momo_transaction_reference'] != null
                  ? 'parsed'
                  : 'needs_review')) {
        _invalid();
      }
    }
    if (data['transaction_reference'] != null &&
        data['transaction_id'] == null) {
      _invalid();
    }
    return SmsReceiptSource._(Map.unmodifiable(data));
  }
}

class SmsReceiptDetail {
  const SmsReceiptDetail(this.source, this.canExtract, this.duplicates);
  final SmsReceiptSource source;
  final bool canExtract;
  final SmsReceiptPage<SmsReceiptSource> duplicates;
}

class SmsExtractionReceipt {
  SmsExtractionReceipt._(this.values);
  final Map<String, dynamic> values;
  factory SmsExtractionReceipt.parse(Map<String, dynamic> data) {
    _keys(data, {
      'request_id',
      'status',
      'resource_type',
      'resource_id',
      'source_kind',
      'source_id',
      'parser_version',
    });
    if (data['status'] != 'succeeded' ||
        data['resource_type'] != 'sms_facts' ||
        data['parser_version'] != smsParserVersion ||
        !smsSourceKinds.contains(data['source_kind']) ||
        ![
          'request_id',
          'resource_id',
          'source_id',
        ].every((key) => _id(data[key]))) {
      _invalid();
    }
    return SmsExtractionReceipt._(Map.unmodifiable(data));
  }
}

class SmsExtractionAttempt {
  SmsExtractionAttempt._(
    this.key,
    this.sourceKind,
    this.sourceId,
    this.body,
    this.authority,
  );
  final String key, sourceKind, sourceId;
  final Map<String, dynamic> body;
  final Object authority;
  String get identity => '$sourceKind/$sourceId';
  String get path => 'sms/receipts/$identity/extract';
}

class SmsExtractionLookup {
  const SmsExtractionLookup(this.status, this.receipt);
  final String status;
  final SmsExtractionReceipt? receipt;
}

class SmsSourceContent {
  const SmsSourceContent(
    this.sourceKind,
    this.sourceId,
    this.sender,
    this.body,
    this.sourceHash,
    this.evidenceLevel,
  );
  final String sourceKind, sourceId, sender, body, sourceHash, evidenceLevel;
}

/// Uncertain requests survive navigation under the same account authority.
final cloudflareAdminSmsAttemptsProvider =
    StateProvider<Map<String, SmsExtractionAttempt>>((ref) {
      ref.watch(
        cloudflareAdminSessionProvider.select(
          (state) => state.asData?.value?.authorityKey,
        ),
      );
      return const {};
    });
final cloudflareAdminSmsApiProvider = Provider<CloudflareAdminSmsApi>((ref) {
  ref.watch(
    cloudflareAdminSessionProvider.select(
      (state) => state.asData?.value?.authorityKey,
    ),
  );
  return CloudflareAdminSmsApi(
    ref.read(cloudflareAdminSessionProvider.notifier),
  );
});

class CloudflareAdminSmsApi {
  CloudflareAdminSmsApi(this.session) : _authority = session.user?.authorityKey;
  final CloudflareAdminSession session;
  final Object? _authority;
  bool get canExtract =>
      _current &&
      session.user!.role != AdminAccountRole.staff &&
      session.user!.permissions.contains('sms.extract');
  bool get canReveal =>
      _current &&
      session.user!.role != AdminAccountRole.staff &&
      session.user!.permissions.contains('sms.reveal');
  bool get _current =>
      _authority != null && session.user?.authorityKey == _authority;
  void _allow(String permission) {
    if (!_current ||
        session.user?.permissions.contains(permission) != true ||
        permission != 'sms.read' &&
            session.user?.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'This SMS action is unavailable to your current account.',
      );
    }
  }

  void _paging(int offset, int limit) {
    if (offset < 0 || offset > 2147483647 || limit < 1 || limit > 100) {
      throw const FormatException('Select a valid receipt page.');
    }
  }

  void _source(String kind, String id) {
    if (!smsSourceKinds.contains(kind) || !_id(id)) {
      throw const FormatException('Select a valid SMS receipt source.');
    }
  }

  Future<Map<String, dynamic>> _read(String path) async {
    _allow('sms.read');
    final result = await session.request('sms/$path', authenticated: true);
    _allow('sms.read');
    return result;
  }

  SmsReceiptPage<SmsReceiptSource> _page(
    Map<String, dynamic> result,
    int offset,
    int limit,
  ) {
    final page = SmsReceiptPage.parse(result, SmsReceiptSource.parse);
    if (page.offset != offset ||
        page.limit != limit ||
        page.rows.map((row) => row.identity).toSet().length !=
            page.rows.length) {
      _invalid();
    }
    return page;
  }

  Future<SmsReceiptPage<SmsReceiptSource>> receipts({
    String search = '',
    String status = '',
    String sourceKind = '',
    String extractionStatus = '',
    String duplicates = '',
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit);
    if (!_text(search, minimum: 0, maximum: 200) ||
        status.isNotEmpty && !smsReceiptStatuses.contains(status) ||
        sourceKind.isNotEmpty && !smsSourceKinds.contains(sourceKind) ||
        extractionStatus.isNotEmpty &&
            !smsExtractionStatuses.contains(extractionStatus) ||
        !{'', 'all', 'conflicting'}.contains(duplicates)) {
      throw const FormatException('Select valid SMS receipt filters.');
    }
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (search.isNotEmpty) 'search': search,
        if (status.isNotEmpty) 'status': status,
        if (sourceKind.isNotEmpty) 'source_kind': sourceKind,
        if (extractionStatus.isNotEmpty) 'extraction_status': extractionStatus,
        if (duplicates.isNotEmpty) 'duplicates': duplicates,
      },
    ).query;
    final page = _page(await _read('receipts?$query'), offset, limit);
    if (page.rows.any(
      (row) =>
          status.isNotEmpty && row.values['status'] != status ||
          sourceKind.isNotEmpty && row.kind != sourceKind ||
          extractionStatus.isNotEmpty &&
              row.extractionStatus != extractionStatus ||
          duplicates.isNotEmpty &&
              row.values[duplicates == 'all'
                      ? 'duplicate_reference_count'
                      : 'conflicting_reference_count'] ==
                  0,
    )) {
      _invalid();
    }
    return page;
  }

  Future<SmsReceiptDetail> detail(
    String sourceKind,
    String id, {
    int offset = 0,
    int limit = 25,
  }) async {
    _source(sourceKind, id);
    _paging(offset, limit);
    final result = await _read(
      'receipts/$sourceKind/$id?limit=$limit&offset=$offset',
    );
    _keys(result, {
      'resource_type',
      'resource',
      'current_actor_id',
      'can_extract',
      'related',
    });
    if (result['resource_type'] != 'sms_receipts' ||
        result['current_actor_id'] != session.user?.id ||
        result['can_extract'] is! bool ||
        result['can_extract'] == true && !canExtract) {
      _invalid();
    }
    final source = SmsReceiptSource.parse(_map(result['resource']));
    if (source.kind != sourceKind || source.id != id) _invalid();
    final related = _map(result['related']);
    _keys(related, {'duplicate_references'});
    final duplicates = _page(
      _map(related['duplicate_references']),
      offset,
      limit,
    );
    if (duplicates.total != source.values['duplicate_reference_count'] ||
        duplicates.rows.any(
          (row) =>
              row.identity == source.identity ||
              row.values['network'] == null ||
              row.values['network'] != source.values['network'] ||
              row.values['momo_transaction_reference'] == null ||
              row.values['momo_transaction_reference'] !=
                  source.values['momo_transaction_reference'],
        )) {
      _invalid();
    }
    return SmsReceiptDetail(source, result['can_extract'] as bool, duplicates);
  }

  SmsExtractionAttempt extract(SmsReceiptSource source, String reason) {
    _allow('sms.extract');
    if (!_text(reason, minimum: 8)) {
      throw const FormatException(
        'Record an extraction reason of 8 to 1000 characters.',
      );
    }
    return SmsExtractionAttempt._(
      const Uuid().v4(),
      source.kind,
      source.id,
      Map.unmodifiable({
        'reason': reason.trim(),
        'expected_source_sha256': source.sourceHash,
      }),
      _authority!,
    );
  }

  SmsExtractionAttempt restoreAttempt({
    required String key,
    required String sourceKind,
    required String sourceId,
    required Map<String, dynamic> body,
  }) {
    _allow('sms.extract');
    _source(sourceKind, sourceId);
    _keys(body, {'reason', 'expected_source_sha256'});
    if (!_id(key) ||
        !_text(body['reason'], minimum: 8) ||
        !_digest(body['expected_source_sha256'])) {
      _invalid();
    }
    return SmsExtractionAttempt._(
      key,
      sourceKind,
      sourceId,
      Map.unmodifiable(body),
      _authority!,
    );
  }

  void _owns(SmsExtractionAttempt attempt, {bool read = false}) {
    _allow(read ? 'sms.read' : 'sms.extract');
    if (attempt.authority != _authority) {
      throw const AdminAccountException(
        'Check this request with the original account authority.',
      );
    }
  }

  SmsExtractionReceipt _receipt(
    Map<String, dynamic> data,
    SmsExtractionAttempt attempt,
  ) {
    final receipt = SmsExtractionReceipt.parse(data);
    if (receipt.values['source_kind'] != attempt.sourceKind ||
        receipt.values['source_id'] != attempt.sourceId) {
      _invalid();
    }
    return receipt;
  }

  Future<SmsExtractionReceipt> submit(SmsExtractionAttempt attempt) async {
    _owns(attempt);
    final result = await session.request(
      attempt.path,
      authenticated: true,
      method: 'POST',
      body: attempt.body,
      idempotencyKey: attempt.key,
    );
    _owns(attempt);
    try {
      return _receipt(result, attempt);
    } on FormatException {
      throw const CloudflareAdminRequestException(
        'The extraction response did not confirm completion. Check the original request receipt.',
        outcomeUnknown: true,
      );
    }
  }

  Future<SmsExtractionLookup> lookup(SmsExtractionAttempt attempt) async {
    _owns(attempt, read: true);
    final result = await _read('requests/${attempt.key}');
    if (result['status'] == 'not_found') {
      _keys(result, {'status'});
      return const SmsExtractionLookup('not_found', null);
    }
    _keys(result, {'status', 'request_id', 'receipt'});
    if (!_id(result['request_id']) ||
        !{'pending', 'succeeded', 'failed'}.contains(result['status'])) {
      _invalid();
    }
    if (result['status'] == 'succeeded') {
      final receipt = _receipt(_map(result['receipt']), attempt);
      if (receipt.values['request_id'] != result['request_id']) _invalid();
      return SmsExtractionLookup('succeeded', receipt);
    }
    if (result['receipt'] != null) _invalid();
    return SmsExtractionLookup(result['status'] as String, null);
  }

  Future<SmsSourceContent> reveal(
    SmsReceiptSource source,
    String reason,
  ) async {
    _allow('sms.reveal');
    if (!_text(reason, minimum: 8)) {
      throw const FormatException(
        'Record a source review reason of 8 to 1000 characters.',
      );
    }
    final result = await session.request(
      'sms/receipts/${source.identity}/content',
      authenticated: true,
      reviewReason: reason.trim(),
    );
    _allow('sms.reveal');
    _keys(result, {
      'source_kind',
      'source_id',
      'raw_sender',
      'raw_body',
      'source_sha256',
      'evidence_level',
      'provider_confirmation',
    });
    if (result['source_kind'] != source.kind ||
        result['source_id'] != source.id ||
        result['source_sha256'] != source.sourceHash ||
        result['evidence_level'] != _evidence(source.kind) ||
        result['provider_confirmation'] != false ||
        !_text(result['raw_sender'], maximum: 80) ||
        result['raw_body'] is! String ||
        (result['raw_body'] as String).isEmpty ||
        (result['raw_body'] as String).length > 16000) {
      _invalid();
    }
    return SmsSourceContent(
      source.kind,
      source.id,
      result['raw_sender'] as String,
      result['raw_body'] as String,
      source.sourceHash,
      result['evidence_level'] as String,
    );
  }
}
