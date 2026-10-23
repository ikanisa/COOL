import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:crypto/crypto.dart';

const rosterActorA = '99710000-0000-4000-8000-000000000001';
const rosterActorB = '99710000-0000-4000-8000-000000000002';
const rosterSessionA = '99710000-0000-4000-8000-000000000003';
const rosterSessionB = '99710000-0000-4000-8000-000000000004';
const rosterImportId = '99710000-0000-4000-8000-000000000005';
const rosterRevisionId = '99710000-0000-4000-8000-000000000006';
const rosterReviewId = '99710000-0000-4000-8000-000000000007';
const rosterCollectionId = '99710000-0000-4000-8000-000000000008';
const rosterExtractionId = '99710000-0000-4000-8000-000000000009';

Map<String, dynamic> previewFixture(
  Map<String, dynamic> body, {
  int count = 2,
  Map<String, dynamic>? parent,
  List<dynamic>? reviewed,
}) {
  final kind = body['source_type'];
  final ai = kind == 'pdf' || kind == 'image';
  final bytes = kind == 'text'
      ? utf8.encode(body['content'] as String)
      : base64Decode(body['content_base64'] as String);
  final rows = [
    for (var i = 0; i < (reviewed?.length ?? count); i++)
      {
        'source_row': i + 1,
        'member_name': reviewed?[i]['member_name'] ?? 'Member ${i + 1}',
        'momo_name': reviewed?[i]['momo_name'] ?? 'MOMO MEMBER ${i + 1}',
        'momo_number':
            reviewed?[i]['momo_number'] ?? '+250788${(100000 + i).toString()}',
        'confidence': ai && reviewed == null ? 0.71 : 1.0,
        'ready': !(ai && reviewed == null),
        'issues': ai && reviewed == null
            ? <String>['Extraction confidence is below 80%']
            : <String>[],
      },
  ];
  return {
    'contract_version': 1,
    'ok': true,
    'import_id': rosterImportId,
    'source_sha256': sha256.convert(bytes).toString(),
    'source_kind': kind,
    'revision_id': parent == null ? rosterRevisionId : rosterReviewId,
    'parent_revision_id': parent?['revision_id'],
    'revision_number': parent == null
        ? 1
        : (parent['revision_number'] as int) + 1,
    'reviewed_rows_sha256': parent == null ? 'a' * 64 : 'b' * 64,
    'can_submit': parent != null,
    'requires_human_review': parent == null,
    'processing_method': parent != null
        ? 'human_review'
        : ai
        ? 'openai_structured_extraction'
        : 'deterministic',
    'model': ai ? 'synthetic-extractor' : null,
    'rows': rows,
    'row_count': rows.length,
    'ready_count': ai && reviewed == null ? 0 : rows.length,
    'error_count': ai && reviewed == null ? rows.length : 0,
    'normalized_rows': [
      for (final row in rows)
        if (row['ready'] == true)
          {
            'member_name': row['member_name'],
            'momo_name': row['momo_name'],
            'momo_number': row['momo_number'],
          },
    ],
    'expires_at': '2026-10-01T12:00:00Z',
    'source_receipt':
        parent?['source_receipt'] ??
        {
          'request_id': body['request_id'],
          'source_size': bytes.length,
          'client_filename': body['filename'] ?? 'pasted-roster.txt',
          'declared_mime': body['mime_type'] ?? 'text/plain',
          'detected_type': {
            'text': 'utf8_text',
            'txt': 'utf8_text',
            'csv': 'utf8_csv',
            'xlsx': 'zip_container',
            'pdf': 'application/pdf',
            'image': body['mime_type'],
          }[kind],
          'derived_sha256': kind == 'xlsx'
              ? sha256
                    .convert(utf8.encode(body['derived_content'] as String))
                    .toString()
              : null,
          'derived_assurance': kind == 'xlsx' ? 'client_derived_tsv' : null,
          'extraction_id': ai ? rosterExtractionId : null,
          'ai_consent': ai,
          'consent_version': ai ? 'roster-ai-extraction-v1' : null,
          'parser_version': 'collect-roster-parser-v1',
          'schema_version': 'collect-roster-rows-v1',
        },
  };
}

Map<String, dynamic> commitFixture(
  Map<String, dynamic> params, {
  int count = 2,
  bool replayed = false,
}) => {
  'contract_version': 1,
  'ok': true,
  'request_id': params['p_request_id'],
  'import_id': params['p_import_id'],
  'revision_id': params['p_revision_id'],
  'reviewed_rows_sha256': params['p_reviewed_rows_sha256'],
  'collection_id': params['p_collection_id'] ?? rosterCollectionId,
  'mode': params['p_mode'],
  'roster_count': count,
  'share_code_ready': true,
  'replayed': replayed,
};

class FakeRosterGateway extends AdminRosterGateway {
  bool current = true;
  bool disposed = false;
  int count = 2;
  final events = StreamController<void>.broadcast(sync: true);
  final prepares = <Map<String, dynamic>>[],
      reviews = <Map<String, dynamic>>[],
      commits = <Map<String, dynamic>>[];
  Map<String, dynamic>? body, latest;
  Future<Object?> Function(Map<String, dynamic>)? onPrepare, onReview, onCommit;
  @override
  bool get isCurrent => current && !disposed;
  @override
  Stream<void> get invalidations => events.stream;
  void invalidate() {
    current = false;
    events.add(null);
  }

  @override
  Future<Object?> prepare(Map<String, dynamic> request) async {
    prepares.add(jsonDecode(jsonEncode(request)) as Map<String, dynamic>);
    body = request;
    if (onPrepare != null) return onPrepare!(request);
    return latest = previewFixture(request, count: count);
  }

  @override
  Future<Object?> review(Map<String, dynamic> request) async {
    reviews.add(jsonDecode(jsonEncode(request)) as Map<String, dynamic>);
    if (onReview != null) return onReview!(request);
    return latest = previewFixture(
      body!,
      parent: latest,
      reviewed: request['p_rows'] as List,
    );
  }

  @override
  Future<Object?> commit(Map<String, dynamic> request) async {
    commits.add(jsonDecode(jsonEncode(request)) as Map<String, dynamic>);
    if (onCommit != null) return onCommit!(request);
    return commitFixture(request, count: count);
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(events.close());
  }
}
