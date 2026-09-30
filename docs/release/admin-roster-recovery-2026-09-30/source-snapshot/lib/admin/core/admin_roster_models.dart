import 'dart:convert';

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
    _exact(value, const {
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
    });
    sourceReceipt = AdminRosterSourceReceipt.fromJson(
      rosterObject(value['source_receipt']),
      sourceKind,
    );
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
  }
  late final AdminRosterSourceReceipt sourceReceipt;
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
    if (sourceReceipt.filename != filename ||
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
