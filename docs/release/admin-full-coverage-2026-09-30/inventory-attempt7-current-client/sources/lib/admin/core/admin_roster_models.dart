import 'dart:convert';
import 'package:crypto/crypto.dart';

String rosterTextDigest(String text) =>
    sha256.convert(utf8.encode(text)).toString();

final rosterUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _sha = RegExp(r'^[0-9a-f]{64}$');
const rosterSourceKinds = {'text', 'csv', 'txt', 'xlsx', 'pdf', 'image'};

Never invalidRosterReceipt() => throw const FormatException(
  'The roster receipt could not be verified. Retry the same request or discard this draft.',
);
Map<String, dynamic> rosterObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    invalidRosterReceipt();
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> row, String key) {
  if (row[key] is! String) invalidRosterReceipt();
  return row[key] as String;
}

String rosterId(Map<String, dynamic> row, String key) {
  final value = _string(row, key);
  if (!rosterUuid.hasMatch(value)) invalidRosterReceipt();
  return value;
}

String _hash(Map<String, dynamic> row, String key) {
  final value = _string(row, key);
  if (!_sha.hasMatch(value)) invalidRosterReceipt();
  return value;
}

int _count(Map<String, dynamic> row, String key, {int max = 500}) {
  final value = row[key];
  if (value is! int || value < 0 || value > max) invalidRosterReceipt();
  return value;
}

bool _bool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! bool) invalidRosterReceipt();
  return value;
}

void _envelope(Map<String, dynamic> row) {
  if (row['contract_version'] != 1 || row['ok'] != true) invalidRosterReceipt();
}

void _exact(Map<String, dynamic> value, Set<String> fields) {
  if (value.length != fields.length ||
      !value.keys.toSet().containsAll(fields)) {
    invalidRosterReceipt();
  }
}

String? _nullableString(Map<String, dynamic> value, String field) {
  if (value[field] != null && value[field] is! String) invalidRosterReceipt();
  return value[field] as String?;
}

DateTime _zonedExpiry(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    invalidRosterReceipt();
  }
  return DateTime.tryParse(value) ?? invalidRosterReceipt();
}

Map<String, dynamic> immutableRosterJson(Map<String, dynamic> value) =>
    Map<String, dynamic>.unmodifiable(jsonDecode(jsonEncode(value)) as Map);

class AdminRosterSourceReceipt {
  AdminRosterSourceReceipt.fromJson(
    Map<String, dynamic> value,
    String sourceKind,
  ) : raw = immutableRosterJson(value),
      requestId = rosterId(value, 'request_id'),
      sourceSize = _count(value, 'source_size', max: 5242880),
      filename = _string(value, 'client_filename'),
      declaredMime = _string(value, 'declared_mime'),
      detectedType = _string(value, 'detected_type'),
      aiConsent = _bool(value, 'ai_consent') {
    const keys = {
      'request_id',
      'source_size',
      'client_filename',
      'declared_mime',
      'detected_type',
      'derived_sha256',
      'derived_assurance',
      'extraction_id',
      'ai_consent',
      'consent_version',
      'parser_version',
      'schema_version',
    };
    if (value.length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        sourceSize < 1 ||
        filename.isEmpty ||
        filename.length > 255 ||
        declaredMime.isEmpty ||
        value['parser_version'] != 'collect-roster-parser-v1' ||
        value['schema_version'] != 'collect-roster-rows-v1') {
      invalidRosterReceipt();
    }
    final ai = const {'pdf', 'image'}.contains(sourceKind);
    if (aiConsent != ai ||
        (ai &&
            (value['consent_version'] != 'roster-ai-extraction-v1' ||
                !rosterUuid.hasMatch('${value['extraction_id']}'))) ||
        (!ai &&
            (value['consent_version'] != null ||
                value['extraction_id'] != null))) {
      invalidRosterReceipt();
    }
    if (sourceKind == 'xlsx') {
      if (!_sha.hasMatch('${value['derived_sha256']}') ||
          value['derived_assurance'] != 'client_derived_tsv' ||
          detectedType != 'zip_container') {
        invalidRosterReceipt();
      }
    } else if (value['derived_sha256'] != null ||
        value['derived_assurance'] != null) {
      invalidRosterReceipt();
    }
    if ((sourceKind == 'text' || sourceKind == 'txt') &&
        detectedType != 'utf8_text') {
      invalidRosterReceipt();
    }
    if (sourceKind == 'csv' && detectedType != 'utf8_csv') {
      invalidRosterReceipt();
    }
    if (sourceKind == 'pdf' && detectedType != 'application/pdf') {
      invalidRosterReceipt();
    }
    if (sourceKind == 'image' &&
        !{'image/png', 'image/jpeg', 'image/webp'}.contains(detectedType)) {
      invalidRosterReceipt();
    }
  }
  final Map<String, dynamic> raw;
  final String requestId, filename, declaredMime, detectedType;
  final int sourceSize;
  final bool aiConsent;
}

class AdminRosterRow {
  AdminRosterRow.fromJson(Map<String, dynamic> row)
    : memberName = _string(row, 'member_name'),
      momoName = _string(row, 'momo_name'),
      momoNumber = _string(row, 'momo_number'),
      sourceRow = _count(row, 'source_row', max: 2147483647),
      ready = _bool(row, 'ready'),
      confidence = row['confidence'] is num
          ? (row['confidence'] as num).toDouble()
          : double.nan,
      issues =
          row['issues'] is List &&
              (row['issues'] as List).every((v) => v is String)
          ? List<String>.unmodifiable(row['issues'] as List)
          : invalidRosterReceipt() {
    _exact(row, const {
      'source_row',
      'member_name',
      'momo_name',
      'momo_number',
      'confidence',
      'issues',
      'ready',
    });
    if (sourceRow == 0 ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        ready != issues.isEmpty ||
        memberName.runes.length > 480 ||
        momoName.runes.length > 480 ||
        momoNumber.runes.length > 32) {
      invalidRosterReceipt();
    }
  }
  final String memberName, momoName, momoNumber;
  final int sourceRow;
  final bool ready;
  final double confidence;
  final List<String> issues;
  Map<String, dynamic> get editable => {
    'member_name': memberName,
    'momo_name': momoName,
    'momo_number': momoNumber,
  };
}

/// A recovered branch retains the genuine original upload proof. Its lookup
/// reference is explicitly distinct from the upload request receipt.
class AdminRosterRecoveryLineage {
  AdminRosterRecoveryLineage.fromJson(Map<String, dynamic> value)
    : raw = immutableRosterJson(value),
      transferRequestId = rosterId(value, 'transfer_request_id'),
      rootImportId = rosterId(value, 'root_import_id'),
      fromImportId = rosterId(value, 'from_import_id'),
      toImportId = rosterId(value, 'to_import_id'),
      actorId = rosterId(value, 'actor_id'),
      destinationSessionId = rosterId(value, 'destination_session_id'),
      destinationReferenceId = rosterId(value, 'destination_reference_id'),
      initialRevisionId = rosterId(value, 'initial_revision_id'),
      originalProof = _string(value, 'original_proof'),
      originalProofSha256 = _hash(value, 'original_proof_sha256') {
    _exact(value, const {
      'contract_version',
      'transfer_request_id',
      'root_import_id',
      'from_import_id',
      'to_import_id',
      'actor_id',
      'destination_session_id',
      'destination_reference_id',
      'initial_revision_id',
      'original_proof',
      'original_proof_sha256',
    });
    if (value['contract_version'] != 1 ||
        fromImportId == toImportId ||
        utf8.encode(originalProof).length > 32000 ||
        rosterTextDigest(originalProof) != originalProofSha256) {
      invalidRosterReceipt();
    }
    proof = rosterObject(jsonDecode(originalProof));
    _exact(proof, const {
      'contract_version',
      'root_import_id',
      'upload_request_id',
      'actor_id',
      'session_id',
      'source_kind',
      'source_sha256',
      'input_sha256',
      'expires_at',
      'source_receipt',
      'resource_reservation_id',
      'decoder_receipt_sha256',
      'decoder_build_sha256',
    });
    if (proof['contract_version'] != 1 ||
        rosterId(proof, 'root_import_id') != rootImportId ||
        rosterId(proof, 'actor_id') != actorId ||
        rosterId(proof, 'session_id') == destinationSessionId ||
        !rosterSourceKinds.contains(proof['source_kind'])) {
      invalidRosterReceipt();
    }
    rosterId(proof, 'upload_request_id');
    _hash(proof, 'source_sha256');
    _hash(proof, 'input_sha256');
    _zonedExpiry(proof['expires_at']);
    for (final field in [
      'resource_reservation_id',
      'decoder_receipt_sha256',
      'decoder_build_sha256',
    ]) {
      if (proof[field] != null) {
        if (field == 'resource_reservation_id') {
          rosterId(proof, field);
        } else {
          _hash(proof, field);
        }
      }
    }
  }
  final Map<String, dynamic> raw;
  late final Map<String, dynamic> proof;
  final String transferRequestId,
      rootImportId,
      fromImportId,
      toImportId,
      actorId,
      destinationSessionId,
      destinationReferenceId,
      initialRevisionId,
      originalProof,
      originalProofSha256;
  String get ownerDigest => rosterTextDigest(
    'collect-roster-owner-v1:$actorId:$destinationSessionId',
  );

  void validatePreview(AdminRosterPreview preview) {
    final source = rosterObject(proof['source_receipt']);
    if (toImportId != preview.importId ||
        proof['source_kind'] != preview.sourceKind ||
        proof['source_sha256'] != preview.sourceSha256 ||
        _zonedExpiry(proof['expires_at']) != preview.expiresAt ||
        proof['upload_request_id'] != preview.sourceReceipt.requestId ||
        !source.entries.every(
          (e) => preview.sourceReceipt.raw[e.key] == e.value,
        ) ||
        source.length != preview.sourceReceipt.raw.length ||
        (!preview.isHumanReview && initialRevisionId != preview.revisionId)) {
      invalidRosterReceipt();
    }
  }
}

class AdminRosterPreview {
  AdminRosterPreview.fromJson(Map<String, dynamic> value)
    : raw = immutableRosterJson(value),
      importId = rosterId(value, 'import_id'),
      revisionId = rosterId(value, 'revision_id'),
      sourceSha256 = _hash(value, 'source_sha256'),
      reviewedRowsSha256 = _hash(value, 'reviewed_rows_sha256'),
      sourceKind = _string(value, 'source_kind'),
      processingMethod = _string(value, 'processing_method'),
      parentRevisionId = _nullableString(value, 'parent_revision_id'),
      revisionNumber = _count(value, 'revision_number', max: 20),
      canSubmit = _bool(value, 'can_submit'),
      requiresHumanReview = _bool(value, 'requires_human_review'),
      rowCount = _count(value, 'row_count'),
      readyCount = _count(value, 'ready_count'),
      errorCount = _count(value, 'error_count'),
      model = _nullableString(value, 'model'),
      expiresAt = _zonedExpiry(value['expires_at']),
      rows = value['rows'] is List
          ? List<AdminRosterRow>.unmodifiable(
              (value['rows'] as List).map(
                (r) => AdminRosterRow.fromJson(rosterObject(r)),
              ),
            )
          : invalidRosterReceipt() {
    _envelope(value);
    _exact(value, {
      'contract_version',
      'ok',
      'import_id',
      'source_sha256',
      'source_kind',
      'source_receipt',
      'revision_id',
      'parent_revision_id',
      'revision_number',
      'reviewed_rows_sha256',
      'can_submit',
      'requires_human_review',
      'processing_method',
      'model',
      'rows',
      'row_count',
      'ready_count',
      'error_count',
      'normalized_rows',
      'expires_at',
      if (value.containsKey('recovery_lineage')) 'recovery_lineage',
    });
    sourceReceipt = AdminRosterSourceReceipt.fromJson(
      rosterObject(value['source_receipt']),
      sourceKind,
    );
    recoveryLineage = value.containsKey('recovery_lineage')
        ? AdminRosterRecoveryLineage.fromJson(
            rosterObject(value['recovery_lineage']),
          )
        : null;
    if (!rosterSourceKinds.contains(sourceKind) ||
        rowCount < 1 ||
        rows.length != rowCount ||
        readyCount != rows.where((r) => r.ready).length ||
        errorCount != rowCount - readyCount ||
        revisionNumber < 1 ||
        (parentRevisionId != null && !rosterUuid.hasMatch(parentRevisionId!)) ||
        !{
          'deterministic',
          'openai_structured_extraction',
          'human_review',
        }.contains(processingMethod)) {
      invalidRosterReceipt();
    }
    if (isHumanReview) {
      if (requiresHumanReview ||
          errorCount != 0 ||
          parentRevisionId == null ||
          revisionNumber < 2) {
        invalidRosterReceipt();
      }
    } else if (canSubmit ||
        !requiresHumanReview ||
        parentRevisionId != null ||
        revisionNumber != 1) {
      invalidRosterReceipt();
    }
    if ((const {'pdf', 'image'}.contains(sourceKind) &&
            (model == null || model!.isEmpty || model!.length > 128)) ||
        (!const {'pdf', 'image'}.contains(sourceKind) && model != null)) {
      invalidRosterReceipt();
    }
    final normalized = value['normalized_rows'];
    if (normalized is! List || normalized.length != readyCount) {
      invalidRosterReceipt();
    }
    final readyRows = rows.where((r) => r.ready).toList();
    for (var i = 0; i < normalized.length; i++) {
      final canonical = rosterObject(normalized[i]);
      if (canonical.length != 3 ||
          canonical['member_name'] != readyRows[i].memberName ||
          canonical['momo_name'] != readyRows[i].momoName ||
          canonical['momo_number'] != readyRows[i].momoNumber) {
        invalidRosterReceipt();
      }
    }
    recoveryLineage?.validatePreview(this);
  }
  late final AdminRosterSourceReceipt sourceReceipt;
  late final AdminRosterRecoveryLineage? recoveryLineage;
  final Map<String, dynamic> raw;
  final String importId,
      revisionId,
      sourceSha256,
      reviewedRowsSha256,
      sourceKind,
      processingMethod;
  final String? parentRevisionId, model;
  final int revisionNumber, rowCount, readyCount, errorCount;
  final bool canSubmit, requiresHumanReview;
  final DateTime expiresAt;
  final List<AdminRosterRow> rows;
  bool get isHumanReview => processingMethod == 'human_review';
  void validateInitial({
    required String sourceKind,
    required String sourceSha256,
    required String requestId,
    required int sourceSize,
    required String filename,
    required String declaredMime,
    String? derivedSha256,
  }) {
    if (recoveryLineage != null ||
        sourceReceipt.filename != filename ||
        sourceReceipt.declaredMime != declaredMime ||
        sourceReceipt.requestId != requestId ||
        sourceReceipt.sourceSize != sourceSize ||
        sourceReceipt.raw['derived_sha256'] != derivedSha256 ||
        isHumanReview ||
        this.sourceKind != sourceKind ||
        this.sourceSha256 != sourceSha256 ||
        (const {'pdf', 'image'}.contains(sourceKind) !=
            (processingMethod == 'openai_structured_extraction'))) {
      invalidRosterReceipt();
    }
  }

  void validateRevision(AdminRosterPreview parent, int expectedRows) {
    if (!isHumanReview ||
        importId != parent.importId ||
        sourceSha256 != parent.sourceSha256 ||
        sourceKind != parent.sourceKind ||
        parentRevisionId != parent.revisionId ||
        revisionId == parent.revisionId ||
        revisionNumber != parent.revisionNumber + 1 ||
        rowCount != expectedRows ||
        expiresAt != parent.expiresAt ||
        model != parent.model ||
        jsonEncode(recoveryLineage?.raw) !=
            jsonEncode(parent.recoveryLineage?.raw) ||
        !sourceReceipt.raw.entries.every(
          (entry) => parent.sourceReceipt.raw[entry.key] == entry.value,
        )) {
      invalidRosterReceipt();
    }
  }
}

class AdminRosterCommit {
  AdminRosterCommit.fromJson(
    Map<String, dynamic> value, {
    required Map<String, dynamic> request,
    required int expectedCount,
  }) : collectionId = rosterId(value, 'collection_id'),
       rosterCount = _count(value, 'roster_count'),
       shareCodeReady = _bool(value, 'share_code_ready'),
       replayed = _bool(value, 'replayed') {
    _envelope(value);
    if (value.keys.toSet().difference(const {
          'contract_version',
          'ok',
          'request_id',
          'import_id',
          'revision_id',
          'reviewed_rows_sha256',
          'collection_id',
          'mode',
          'roster_count',
          'share_code_ready',
          'replayed',
        }).isNotEmpty ||
        value.length != 11) {
      invalidRosterReceipt();
    }
    for (final field in ['request_id', 'import_id', 'revision_id']) {
      if (rosterId(value, field) != request['p_$field']) invalidRosterReceipt();
    }
    if (_hash(value, 'reviewed_rows_sha256') !=
            request['p_reviewed_rows_sha256'] ||
        value['mode'] != request['p_mode'] ||
        !{'create', 'existing'}.contains(value['mode']) ||
        rosterCount != expectedCount ||
        rosterCount < 1 ||
        !shareCodeReady ||
        (value['mode'] == 'existing' &&
            collectionId != request['p_collection_id'])) {
      invalidRosterReceipt();
    }
  }
  final String collectionId;
  final int rosterCount;
  final bool shareCodeReady, replayed;
}

/// A status read is useful only when its immutable source and latest revision
/// belong to the draft being recovered. It never grants a new write by itself.
class AdminRosterStatus {
  AdminRosterStatus.fromJson(
    Map<String, dynamic> value, {
    required AdminRosterPreview source,
    required AdminRosterPreview current,
  }) : state = _string(value, 'state'),
       expiresAt = _zonedExpiry(value['expires_at']) {
    _envelope(value);
    _exact(value, const {
      'contract_version',
      'ok',
      'import_id',
      'state',
      'expires_at',
      'preview',
      'commit',
      'error_code',
    });
    if (rosterId(value, 'import_id') != source.importId ||
        expiresAt != source.expiresAt ||
        !{'preview_ready', 'committed'}.contains(state) ||
        value['error_code'] != null) {
      invalidRosterReceipt();
    }
    preview = AdminRosterPreview.fromJson(rosterObject(value['preview']));
    if (preview.importId != source.importId ||
        preview.sourceSha256 != source.sourceSha256 ||
        preview.sourceKind != source.sourceKind ||
        preview.model != source.model ||
        preview.expiresAt != source.expiresAt ||
        !preview.sourceReceipt.raw.entries.every(
          (e) => source.sourceReceipt.raw[e.key] == e.value,
        ) ||
        preview.revisionNumber < current.revisionNumber) {
      invalidRosterReceipt();
    }
    if (preview.revisionNumber == current.revisionNumber &&
        (preview.revisionId != current.revisionId ||
            preview.parentRevisionId != current.parentRevisionId ||
            preview.reviewedRowsSha256 != current.reviewedRowsSha256 ||
            preview.rowCount != current.rowCount ||
            jsonEncode(preview.raw['rows']) !=
                jsonEncode(current.raw['rows']))) {
      invalidRosterReceipt();
    }
    if (state == 'committed') {
      if (!preview.isHumanReview || preview.canSubmit) invalidRosterReceipt();
      commit = immutableRosterJson(rosterObject(value['commit']));
      // Validate every field even when this is another request's completion.
      AdminRosterCommit.fromJson(
        commit!,
        request: {
          'p_request_id': rosterId(commit!, 'request_id'),
          'p_import_id': source.importId,
          'p_revision_id': preview.revisionId,
          'p_reviewed_rows_sha256': preview.reviewedRowsSha256,
          'p_mode': commit!['mode'],
          'p_collection_id': commit!['collection_id'],
        },
        expectedCount: preview.rowCount,
      );
    } else if (value['commit'] != null) {
      invalidRosterReceipt();
    }
  }
  final String state;
  final DateTime expiresAt;
  late final AdminRosterPreview preview;
  Map<String, dynamic>? commit;
}

/// Exact text is hashed before parsing: JSON key order/spacing need not match
/// PostgreSQL's jsonb serialization. This is the persisted execution payload.
Map<String, dynamic> decodeRosterRecoveryPayload(
  String text,
  String digest, {
  required String kind,
}) {
  if (utf8.encode(text).length > 512000 || rosterTextDigest(text) != digest) {
    invalidRosterReceipt();
  }
  final value = rosterObject(jsonDecode(text));
  final keys = kind == 'draft'
      ? const {'parent_revision_id', 'rows', 'reason', 'title'}
      : kind == 'review'
      ? const {
          'p_import_id',
          'p_parent_revision_id',
          'p_reason',
          'p_request_id',
          'p_rows',
        }
      : kind == 'commit'
      ? const {
          'p_request_id',
          'p_import_id',
          'p_revision_id',
          'p_reviewed_rows_sha256',
          'p_human_affirmed',
          'p_mode',
          'p_collection_id',
          'p_title',
          'p_reason',
        }
      : <String>{};
  _exact(value, keys);
  if (kind == 'draft' || kind == 'review') {
    rosterId(
      value,
      kind == 'draft' ? 'parent_revision_id' : 'p_parent_revision_id',
    );
    final rows = value[kind == 'draft' ? 'rows' : 'p_rows'];
    if (rows is! List || rows.isEmpty || rows.length > 500) {
      invalidRosterReceipt();
    }
    for (final item in rows) {
      final row = rosterObject(item);
      _exact(row, const {'member_name', 'momo_name', 'momo_number'});
      for (final f in ['member_name', 'momo_name', 'momo_number']) {
        if (_string(row, f).runes.length > (f == 'momo_number' ? 32 : 480)) {
          invalidRosterReceipt();
        }
      }
    }
  }
  if (kind == 'draft') {
    if (_string(value, 'title').runes.length > 120 ||
        _string(value, 'reason').runes.length > 500) {
      invalidRosterReceipt();
    }
  } else {
    rosterId(value, 'p_import_id');
    rosterId(value, 'p_request_id');
    if (_string(value, 'p_reason').trim().runes.length < 8 ||
        _string(value, 'p_reason').runes.length > 500) {
      invalidRosterReceipt();
    }
    if (kind == 'commit') {
      rosterId(value, 'p_revision_id');
      _hash(value, 'p_reviewed_rows_sha256');
      if (value['p_human_affirmed'] != true ||
          !{'create', 'existing'}.contains(value['p_mode'])) {
        invalidRosterReceipt();
      }
      if (value['p_mode'] == 'existing') {
        rosterId(value, 'p_collection_id');
        if (value['p_title'] != null) invalidRosterReceipt();
      } else if (value['p_collection_id'] != null ||
          _string(value, 'p_title').trim().runes.length < 3 ||
          _string(value, 'p_title').runes.length > 120) {
        invalidRosterReceipt();
      }
    }
  }
  return value;
}

class AdminRosterRecovery {
  AdminRosterRecovery.fromJson(
    Map<String, dynamic> raw, {
    required String uploadRequestId,
    required String sourceSha256,
    String? importId,
    String? pendingRequestId,
    String? pendingSha256,
  }) {
    _envelope(raw);
    _exact(raw, const {
      'contract_version',
      'ok',
      'upload_request_id',
      'import_id',
      'source_sha256',
      'state',
      'initial_preview',
      'status',
      'requested_intent_id',
      'intent',
      'draft',
    });
    if (rosterId(raw, 'upload_request_id') != uploadRequestId ||
        raw['requested_intent_id'] != pendingRequestId) {
      invalidRosterReceipt();
    }
    state = _string(raw, 'state');
    if (!{
      'missing_source',
      'awaiting_preview',
      'failed',
      'expired',
      'preview_ready',
      'committed',
    }.contains(state)) {
      invalidRosterReceipt();
    }
    if (state == 'missing_source') {
      if (raw['import_id'] != null ||
          raw['source_sha256'] != null ||
          raw['initial_preview'] != null ||
          raw['status'] != null ||
          raw['draft'] != null ||
          raw['intent'] != null) {
        invalidRosterReceipt();
      }
      return;
    }
    this.importId = rosterId(raw, 'import_id');
    if (importId != null && this.importId != importId ||
        _hash(raw, 'source_sha256') != sourceSha256) {
      invalidRosterReceipt();
    }
    if (state == 'expired') {
      if (raw['initial_preview'] != null ||
          raw['status'] != null ||
          raw['draft'] != null ||
          raw['intent'] != null) {
        invalidRosterReceipt();
      }
      return;
    }
    if (state == 'awaiting_preview' || state == 'failed') {
      final status = rosterObject(raw['status']);
      _exact(status, const {
        'contract_version',
        'ok',
        'import_id',
        'state',
        'expires_at',
        'preview',
        'commit',
        'error_code',
      });
      _envelope(status);
      if (status['state'] != state ||
          rosterId(status, 'import_id') != this.importId ||
          status['preview'] != null ||
          status['commit'] != null ||
          raw['initial_preview'] != null ||
          raw['intent'] != null ||
          raw['draft'] != null) {
        invalidRosterReceipt();
      }
      _zonedExpiry(status['expires_at']);
      return;
    }
    initial = AdminRosterPreview.fromJson(rosterObject(raw['initial_preview']));
    if (initial!.importId != this.importId ||
        (initial!.recoveryLineage?.destinationReferenceId ??
                initial!.sourceReceipt.requestId) !=
            uploadRequestId ||
        initial!.sourceSha256 != sourceSha256 ||
        initial!.isHumanReview) {
      invalidRosterReceipt();
    }
    status = AdminRosterStatus.fromJson(
      rosterObject(raw['status']),
      source: initial!,
      current: initial!,
    );
    if (status!.state != state) invalidRosterReceipt();
    if (raw['intent'] != null) {
      final i = rosterObject(raw['intent']);
      _exact(i, const {
        'request_id',
        'kind',
        'payload_sha256',
        'payload',
        'result',
        'expired',
      });
      if (rosterId(i, 'request_id') != pendingRequestId ||
          _hash(i, 'payload_sha256') != pendingSha256 ||
          !{'review', 'commit'}.contains(i['kind']) ||
          i['expired'] is! bool) {
        invalidRosterReceipt();
      }
      intentKind = i['kind'] as String;
      if (i['expired'] == true) {
        if (i['payload'] != null) invalidRosterReceipt();
      } else {
        intentText = _string(i, 'payload');
        intent = decodeRosterRecoveryPayload(
          intentText!,
          pendingSha256!,
          kind: intentKind!,
        );
        if (intent!['p_request_id'] != pendingRequestId ||
            intent!['p_import_id'] != this.importId) {
          invalidRosterReceipt();
        }
      }
      intentResult = i['result'] == null ? null : rosterObject(i['result']);
      if (intentResult != null && intent != null) {
        if (intentKind == 'commit') {
          AdminRosterCommit.fromJson(
            intentResult!,
            request: intent!,
            expectedCount: status!.preview.rowCount,
          );
        } else {
          final r = AdminRosterPreview.fromJson(intentResult!);
          if (r.importId != this.importId ||
              r.parentRevisionId != intent!['p_parent_revision_id'] ||
              !r.isHumanReview ||
              r.rowCount != (intent!['p_rows'] as List).length ||
              r.sourceSha256 != initial!.sourceSha256 ||
              r.expiresAt != initial!.expiresAt ||
              r.revisionNumber > status!.preview.revisionNumber) {
            invalidRosterReceipt();
          }
        }
      }
    }
    if (raw['draft'] != null) {
      final d = rosterObject(raw['draft']);
      _exact(d, const {'checkpoint_id', 'payload_sha256', 'payload'});
      checkpointId = rosterId(d, 'checkpoint_id');
      draft = decodeRosterRecoveryPayload(
        _string(d, 'payload'),
        _hash(d, 'payload_sha256'),
        kind: 'draft',
      );
    }
  }
  late final String state;
  String? importId, intentKind, intentText, checkpointId;
  AdminRosterPreview? initial;
  AdminRosterStatus? status;
  Map<String, dynamic>? intent, intentResult, draft;
}

class AdminRosterInterruption {
  AdminRosterInterruption.fromJson(Map<String, dynamic> value)
    : importId = rosterId(value, 'import_id'),
      sourceSha256 = _hash(value, 'source_sha256'),
      sourceKind = _string(value, 'source_kind'),
      state = _string(value, 'state'),
      etag = _nullableString(value, 'etag'),
      createdAt = _zonedExpiry(value['created_at']),
      expiresAt = _zonedExpiry(value['expires_at']) {
    _exact(value, const {
      'import_id',
      'source_sha256',
      'source_kind',
      'state',
      'etag',
      'created_at',
      'expires_at',
    });
    if (!rosterSourceKinds.contains(sourceKind) ||
        !{'interrupted', 'committed'}.contains(state) ||
        !expiresAt.isAfter(createdAt) ||
        (state == 'interrupted' ? !_sha.hasMatch(etag ?? '') : etag != null)) {
      invalidRosterReceipt();
    }
  }
  final String importId, sourceSha256, sourceKind, state;
  final String? etag;
  final DateTime createdAt, expiresAt;
}

class AdminRosterInterruptedList {
  AdminRosterInterruptedList.fromJson(
    Map<String, dynamic> value,
    String expectedOwnerDigest,
  ) {
    _envelope(value);
    _exact(value, const {
      'contract_version',
      'ok',
      'actor_id',
      'destination_session_id',
      'items',
    });
    actorId = rosterId(value, 'actor_id');
    sessionId = rosterId(value, 'destination_session_id');
    if (rosterTextDigest('collect-roster-owner-v1:$actorId:$sessionId') !=
            expectedOwnerDigest ||
        value['items'] is! List ||
        (value['items'] as List).length > 100) {
      invalidRosterReceipt();
    }
    items = List.unmodifiable(
      (value['items'] as List).map(
        (v) => AdminRosterInterruption.fromJson(rosterObject(v)),
      ),
    );
    if (items.map((i) => i.importId).toSet().length != items.length) {
      invalidRosterReceipt();
    }
  }
  late final String actorId, sessionId;
  late final List<AdminRosterInterruption> items;
}

class AdminRosterInterruptedInspection {
  AdminRosterInterruptedInspection.fromJson(
    Map<String, dynamic> value,
    AdminRosterInterruption selected,
    String ownerDigest,
  ) {
    _envelope(value);
    _exact(value, const {
      'contract_version',
      'ok',
      'import_id',
      'actor_id',
      'destination_session_id',
      'etag',
      'initial_preview',
      'latest_preview',
      'draft_payload',
      'draft_sha256',
      'expires_at',
    });
    final actor = rosterId(value, 'actor_id'),
        session = rosterId(value, 'destination_session_id');
    initial = AdminRosterPreview.fromJson(
      rosterObject(value['initial_preview']),
    );
    latest = AdminRosterPreview.fromJson(rosterObject(value['latest_preview']));
    if (rosterId(value, 'import_id') != selected.importId ||
        _hash(value, 'etag') != selected.etag ||
        rosterTextDigest('collect-roster-owner-v1:$actor:$session') !=
            ownerDigest ||
        initial.importId != selected.importId ||
        initial.isHumanReview ||
        latest.importId != initial.importId ||
        initial.sourceSha256 != selected.sourceSha256 ||
        latest.sourceSha256 != initial.sourceSha256 ||
        initial.expiresAt != selected.expiresAt ||
        latest.expiresAt != initial.expiresAt ||
        _zonedExpiry(value['expires_at']) != initial.expiresAt ||
        jsonEncode(latest.sourceReceipt.raw) !=
            jsonEncode(initial.sourceReceipt.raw)) {
      invalidRosterReceipt();
    }
    draftPayload = _string(value, 'draft_payload');
    draftSha256 = _hash(value, 'draft_sha256');
    draft = decodeRosterRecoveryPayload(
      draftPayload,
      draftSha256,
      kind: 'draft',
    );
    if (draft['parent_revision_id'] != latest.revisionId) {
      invalidRosterReceipt();
    }
  }
  late final AdminRosterPreview initial, latest;
  late final String draftPayload, draftSha256;
  late final Map<String, dynamic> draft;
}

class AdminRosterTransferAck {
  AdminRosterTransferAck.fromJson(
    Map<String, dynamic> value, {
    required Map<String, dynamic> request,
    required String ownerDigest,
    required AdminRosterInterruptedInspection inspected,
  }) {
    _envelope(value);
    _exact(value, const {
      'contract_version',
      'ok',
      'state',
      'request_id',
      'from_import_id',
      'root_import_id',
      'to_import_id',
      'actor_id',
      'destination_session_id',
      'destination_reference_id',
      'initial_revision_id',
      'checkpoint_id',
      'draft_sha256',
      'source_etag',
      'original_proof_sha256',
      'expires_at',
    });
    requestId = rosterId(value, 'request_id');
    fromImportId = rosterId(value, 'from_import_id');
    rootImportId = rosterId(value, 'root_import_id');
    toImportId = rosterId(value, 'to_import_id');
    destinationReferenceId = rosterId(value, 'destination_reference_id');
    initialRevisionId = rosterId(value, 'initial_revision_id');
    checkpointId = rosterId(value, 'checkpoint_id');
    draftSha256 = _hash(value, 'draft_sha256');
    originalProofSha256 = _hash(value, 'original_proof_sha256');
    expiresAt = _zonedExpiry(value['expires_at']);
    final actor = rosterId(value, 'actor_id'),
        sid = rosterId(value, 'destination_session_id');
    if (value['state'] != 'transferred' ||
        requestId != request['p_request_id'] ||
        fromImportId != request['p_import_id'] ||
        fromImportId != inspected.initial.importId ||
        toImportId == fromImportId ||
        value['source_etag'] != request['p_etag'] ||
        rootImportId !=
            (inspected.initial.recoveryLineage?.rootImportId ??
                inspected.initial.importId) ||
        expiresAt != inspected.initial.expiresAt ||
        rosterTextDigest('collect-roster-owner-v1:$actor:$sid') !=
            ownerDigest ||
        request['p_human_affirmed'] != true) {
      invalidRosterReceipt();
    }
  }
  late final String requestId,
      fromImportId,
      rootImportId,
      toImportId,
      destinationReferenceId,
      initialRevisionId,
      checkpointId,
      draftSha256,
      originalProofSha256;
  late final DateTime expiresAt;
}
