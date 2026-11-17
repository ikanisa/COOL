import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

/// This remains off until the managed-Admin observation API is qualified.
final burimunsiObservationEnabledProvider = Provider<bool>(
  (_) => const bool.fromEnvironment('BURIMUNSI_ADMIN_OBSERVATIONS_ENABLED'),
);

/// Optional text hints have a separate, default-off public build flag.
final burimunsiObservationHintsEnabledProvider = Provider<bool>(
  (_) =>
      const bool.fromEnvironment('BURIMUNSI_ADMIN_OBSERVATION_HINTS_ENABLED'),
);
final burimunsiObservationClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final cloudflareAdminObservationApiProvider =
    Provider<CloudflareAdminObservationApi>((ref) {
      ref.watch(cloudflareAdminSessionProvider);
      return CloudflareAdminObservationApi(
        ref.read(cloudflareAdminSessionProvider.notifier),
        displayHints: ref.watch(burimunsiObservationHintsEnabledProvider),
      );
    });

final _collectionId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _digest = RegExp(r'^[a-f0-9]{64}$');
final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
Never _invalid() => throw const FormatException(
  'The observation response could not be verified.',
);

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(Map<String, dynamic> data, Set<String> expected) {
  if (data.length != expected.length || !data.keys.every(expected.contains)) {
    _invalid();
  }
}

String _group(Object? value) =>
    value is String && _collectionId.hasMatch(value) ? value : _invalid();
String _id(Object? value) =>
    value is String && _uuid.hasMatch(value) ? value : _invalid();

DateTime _utc(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$',
      ).hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    _invalid();
  }
  return parsed;
}

class ObservationCollection {
  const ObservationCollection(this.id, this.label);
  final String id, label;
  factory ObservationCollection.parse(Object? value) {
    final data = _object(value);
    _keys(data, {'collectionId', 'label'});
    final label = data['label'];
    if (label is! String ||
        label.trim().isEmpty ||
        label.length > 200 ||
        _controls.hasMatch(label)) {
      _invalid();
    }
    return ObservationCollection(_group(data['collectionId']), label);
  }
}

class ObservationCollections {
  const ObservationCollections(this.items, this.asOf);
  final List<ObservationCollection> items;
  final DateTime asOf;
  factory ObservationCollections.parse(Map<String, dynamic> data) {
    _keys(data, {'contractVersion', 'items', 'asOf'});
    if (data['contractVersion'] != 1 ||
        data['items'] is! List ||
        (data['items'] as List).length > 500) {
      _invalid();
    }
    final items = (data['items'] as List)
        .map(ObservationCollection.parse)
        .toList(growable: false);
    if (items.map((item) => item.id).toSet().length != items.length) _invalid();
    return ObservationCollections(List.unmodifiable(items), _utc(data['asOf']));
  }
}

class ObservationAdmission {
  const ObservationAdmission(
    this.requestId,
    this.sourceId,
    this.admittedAt,
    this.retentionState,
    this.bodySha256,
  );
  final String requestId, sourceId, retentionState;
  final DateTime admittedAt;
  final String? bodySha256;
  bool get retained => retentionState == 'retained';
  factory ObservationAdmission.parse(Object? value) {
    final data = _object(value);
    _keys(data, {
      'requestId',
      'sourceId',
      'admittedAt',
      'retentionState',
      'bodySha256',
    });
    final state = data['retentionState'], hash = data['bodySha256'];
    if (state != 'retained' && state != 'unresolved' ||
        state == 'retained' && (hash is! String || !_digest.hasMatch(hash)) ||
        state == 'unresolved' && hash != null) {
      _invalid();
    }
    return ObservationAdmission(
      _id(data['requestId']),
      _id(data['sourceId']),
      _utc(data['admittedAt']),
      state as String,
      hash as String?,
    );
  }
}

class ObservationAdmissionPage {
  const ObservationAdmissionPage(
    this.collectionId,
    this.items,
    this.nextCursor,
    this.asOf,
  );
  final String collectionId;
  final List<ObservationAdmission> items;
  final String? nextCursor;
  final DateTime asOf;
  factory ObservationAdmissionPage.parse(
    Map<String, dynamic> data,
    String expectedCollection,
    int limit,
  ) {
    _keys(data, {
      'contractVersion',
      'collectionId',
      'items',
      'nextCursor',
      'asOf',
    });
    if (data['contractVersion'] != 1 ||
        _group(data['collectionId']) != expectedCollection ||
        data['items'] is! List ||
        (data['items'] as List).length > limit) {
      _invalid();
    }
    final cursor = data['nextCursor'];
    if (cursor != null &&
        (cursor is! String ||
            cursor.isEmpty ||
            cursor.length > 2048 ||
            _controls.hasMatch(cursor))) {
      _invalid();
    }
    final items = (data['items'] as List)
        .map(ObservationAdmission.parse)
        .toList(growable: false);
    if (items.map((item) => item.sourceId).toSet().length != items.length) {
      _invalid();
    }
    return ObservationAdmissionPage(
      expectedCollection,
      List.unmodifiable(items),
      cursor as String?,
      _utc(data['asOf']),
    );
  }
}

class ObservationDisplayHint {
  const ObservationDisplayHint(this.kind, this.text, this.start, this.end);
  final String kind, text;
  final int start, end;
}

class ObservationDisplayHints {
  const ObservationDisplayHints(
    this.profileVersion,
    this.profileSha256,
    this.hints,
  );
  final String profileVersion, profileSha256;
  final List<ObservationDisplayHint> hints;

  factory ObservationDisplayHints.parse(
    Object? value,
    String body,
    String hash,
  ) {
    final data = _object(value);
    _keys(data, {
      'schemaVersion',
      'kind',
      'profileVersion',
      'profileSha256',
      'bodySha256',
      'hints',
    });
    final version = data['profileVersion'];
    final profileHash = data['profileSha256'];
    final values = data['hints'];
    if (data['schemaVersion'] is! int ||
        data['schemaVersion'] != 1 ||
        data['kind'] != 'partial_inbox_display_only' ||
        version is! String ||
        version.isEmpty ||
        version.length > 128 ||
        _controls.hasMatch(version) ||
        profileHash is! String ||
        !_digest.hasMatch(profileHash) ||
        data['bodySha256'] != hash ||
        values is! List ||
        values.isEmpty ||
        values.length > 2) {
      _invalid();
    }
    final kinds = <String>{};
    final hints = <ObservationDisplayHint>[];
    for (final value in values) {
      final item = _object(value);
      _keys(item, {'kind', 'text', 'start', 'end'});
      final kind = item['kind'], text = item['text'];
      final start = item['start'], end = item['end'];
      if (kind is! String ||
          !{'quoted_incoming_amount', 'quoted_reference'}.contains(kind) ||
          !kinds.add(kind) ||
          text is! String ||
          text.isEmpty ||
          text.length > 3000 ||
          start is! int ||
          end is! int ||
          start < 0 ||
          start >= end ||
          end > body.length ||
          !_utf16Boundary(body, start) ||
          !_utf16Boundary(body, end) ||
          body.substring(start, end) != text) {
        _invalid();
      }
      hints.add(ObservationDisplayHint(kind, text, start, end));
    }
    return ObservationDisplayHints(
      version,
      profileHash,
      List.unmodifiable(hints),
    );
  }
}

bool _utf16Boundary(String value, int index) {
  if (index == 0 || index == value.length) return true;
  final before = value.codeUnitAt(index - 1), after = value.codeUnitAt(index);
  return !(before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff);
}

class ObservationContent {
  const ObservationContent(this.sender, this.body, {this.displayHints});
  final String sender, body;
  final ObservationDisplayHints? displayHints;
  factory ObservationContent.parse(
    Map<String, dynamic> data,
    String collectionId,
    ObservationAdmission admission, {
    bool displayHintsRequested = false,
  }) {
    _keys(data, {
      'contractVersion',
      'collectionId',
      'sourceId',
      'sourceKind',
      'retentionState',
      'rawSender',
      'rawBody',
      'bodySha256',
      if (displayHintsRequested) 'displayHints',
    });
    final sender = data['rawSender'],
        body = data['rawBody'],
        hash = data['bodySha256'];
    if (!admission.retained ||
        data['contractVersion'] != 1 ||
        data['collectionId'] != collectionId ||
        data['sourceId'] != admission.sourceId ||
        data['sourceKind'] != 'observation' ||
        data['retentionState'] != 'retained' ||
        hash != admission.bodySha256 ||
        sender is! String ||
        sender.trim().isEmpty ||
        sender.length > 96 ||
        _controls.hasMatch(sender) ||
        body is! String ||
        body.isEmpty ||
        body.contains('\u0000') ||
        utf8.encode(body).length > 3000 ||
        sha256.convert(utf8.encode(body)).toString() != hash) {
      _invalid();
    }
    return ObservationContent(
      sender,
      body,
      displayHints: displayHintsRequested && data['displayHints'] != null
          ? ObservationDisplayHints.parse(
              data['displayHints'],
              body,
              hash as String,
            )
          : null,
    );
  }
}

class CloudflareAdminObservationApi {
  CloudflareAdminObservationApi(this.session, {this.displayHints = false})
    : _fence = session.authorityFence;
  final CloudflareAdminSession session;
  final bool displayHints;
  final ({int epoch, Object? key}) _fence;

  void _allow({bool reveal = false}) {
    final user = session.user;
    if (session.authorityFence != _fence ||
        user == null ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        !user.permissions.contains('sms.read') ||
        reveal &&
            (user.role == AdminAccountRole.staff ||
                !user.permissions.contains('sms.reveal'))) {
      throw const AdminAccountException(
        'This SMS action is unavailable to your current account.',
      );
    }
    // The same-session email proof can expire or be removed without changing
    // the authority fence. _read calls this both before and after the response.
    if (reveal && !user.hasRecentSensitiveVerification()) {
      throw CloudflareAdminRequestException(
        user.usesEmailVerification
            ? 'Verify your email before revealing this SMS source.'
            : 'Complete a current verification before revealing this SMS source.',
        code: user.usesEmailVerification
            ? 'recent_email_sign_in_required'
            : 'recent_verification_required',
      );
    }
  }

  Future<Map<String, dynamic>> _read(
    String path, {
    bool reveal = false,
    String? reason,
  }) async {
    _allow(reveal: reveal);
    final data = await session.request(
      path,
      authenticated: true,
      reviewReason: reason,
      responseCurrent: () => session.authorityFence == _fence,
    );
    _allow(reveal: reveal);
    return data;
  }

  Future<ObservationCollections> collections() async =>
      ObservationCollections.parse(
        await _read('momo/observations/collections'),
      );

  Future<ObservationAdmissionPage> admissions(
    String collectionId, {
    String? cursor,
    int limit = 25,
  }) async {
    _group(collectionId);
    if (limit < 1 ||
        limit > 100 ||
        cursor != null &&
            (cursor.isEmpty ||
                cursor.length > 2048 ||
                _controls.hasMatch(cursor))) {
      _invalid();
    }
    final query = Uri(
      queryParameters: {
        'collectionId': collectionId,
        'limit': '$limit',
        'cursor': ?cursor,
      },
    ).query;
    return ObservationAdmissionPage.parse(
      await _read('momo/observations?$query'),
      collectionId,
      limit,
    );
  }

  Future<ObservationContent> reveal(
    String collectionId,
    ObservationAdmission admission,
    String reason,
  ) async {
    _group(collectionId);
    final normalized = reason.trim();
    if (!admission.retained ||
        normalized.length < 8 ||
        normalized.length > 1000 ||
        _controls.hasMatch(normalized)) {
      _invalid();
    }
    final query = Uri(
      queryParameters: {
        'collectionId': collectionId,
        if (displayHints) 'displayHintsVersion': '1',
      },
    ).query;
    final data = await _read(
      'momo/observations/${admission.sourceId}/content?$query',
      reveal: true,
      reason: normalized,
    );
    return ObservationContent.parse(
      data,
      collectionId,
      admission,
      displayHintsRequested: displayHints,
    );
  }
}
