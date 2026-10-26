part of 'admin_roster_import.dart';

String safeRosterFilename(String filename) {
  var safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  if (!RegExp(r'^[A-Za-z0-9]').hasMatch(safe)) safe = 'roster-$safe';
  if (safe.length > 160) {
    final dot = safe.lastIndexOf('.');
    final extension = dot >= 0 && safe.length - dot <= 6
        ? safe.substring(dot)
        : '';
    safe = safe.substring(0, 160 - extension.length) + extension;
  }
  return safe;
}

class AdminRosterUpload {
  AdminRosterUpload._(this.body, this.sourceSha256);
  static const _mimes = {
    'csv': 'text/csv',
    'txt': 'text/plain',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };
  static const _textKinds = {'csv', 'txt'};
  static const _imageKinds = {'png', 'jpg', 'jpeg', 'webp'};
  static const _aiKinds = {'pdf', ..._imageKinds};
  static int _limit(String kind) =>
      _textKinds.contains(kind) ? 512000 : 5242880;
  static String _admitKind(String extension, bool aiConsent) {
    final kind = extension.toLowerCase();
    if (!_mimes.containsKey(kind)) {
      throw StateError('Choose a CSV, TXT, XLSX, PDF, PNG, JPEG or WebP file.');
    }
    if (_aiKinds.contains(kind) && !aiConsent) {
      throw StateError('Confirm OpenAI extraction for this PDF or image.');
    }
    return kind;
  }

  static Never _invalidSize() => throw StateError(
    'The selected roster is empty or exceeds its upload limit.',
  );
  final Map<String, dynamic> body;
  final String sourceSha256;
  int get sourceSize => body['source_type'] == 'text'
      ? utf8.encode(body['content'] as String).length
      : base64Decode(body['content_base64'] as String).length;
  String? get derivedSha256 => body['derived_content'] == null
      ? null
      : sha256
            .convert(utf8.encode(body['derived_content'] as String))
            .toString();
  String get sourceKind => body['source_type'] as String;
  static AdminRosterUpload pasted(String text) {
    final bytes = utf8.encode(text);
    if (bytes.isEmpty || bytes.length > 512000) {
      throw StateError('Paste a roster of up to 512,000 bytes.');
    }
    return AdminRosterUpload._({
      'contract_version': 1,
      'request_id': const Uuid().v4(),
      'source_type': 'text',
      'content': text,
    }, sha256.convert(bytes).toString());
  }

  static Future<AdminRosterUpload> file(
    PlatformFile file, {
    required bool aiConsent,
  }) async {
    final kind = _admitKind(file.extension ?? '', aiConsent);
    final limit = _limit(kind);
    // length() may read the entire source. Only picker metadata is consulted;
    // unknown lengths remain admissible through the bounded stream below.
    final knownLength = file.lengthSync();
    if (knownLength != null && (knownLength <= 0 || knownLength > limit)) {
      _invalidSize();
    }
    final bytes = BytesBuilder();
    var readLength = 0;
    await for (final chunk in file.readAsByteStream()) {
      if (chunk.length > limit - readLength) _invalidSize();
      readLength += chunk.length;
      if (knownLength != null && readLength > knownLength) {
        throw StateError('The selected roster changed while it was read.');
      }
      // The cap is checked before retaining this chunk. BytesBuilder copies
      // accepted bytes so a reused platform buffer cannot change the digest.
      bytes.add(chunk);
    }
    if (knownLength != null && readLength != knownLength) {
      throw StateError('The selected roster changed while it was read.');
    }
    return fromBytes(file.name, kind, bytes.takeBytes(), aiConsent: aiConsent);
  }

  static AdminRosterUpload fromBytes(
    String filename,
    String extension,
    Uint8List bytes, {
    required bool aiConsent,
  }) {
    final kind = _admitKind(extension, aiConsent);
    if (bytes.isEmpty || bytes.length > _limit(kind)) _invalidSize();
    final ai = _aiKinds.contains(kind);
    if (_textKinds.contains(kind)) {
      utf8.decode(
        bytes,
      ); // Reject invalid UTF8 without replacing the original file.
    }
    return AdminRosterUpload._({
      'contract_version': 1,
      'request_id': const Uuid().v4(),
      'source_type': _imageKinds.contains(kind) ? 'image' : kind,
      'filename': safeRosterFilename(filename),
      'mime_type': _mimes[kind],
      'content_base64': base64Encode(bytes),
      if (kind == 'xlsx') 'derived_content': decodeRosterXlsx(bytes),
      if (ai) ...{
        'ai_consent': true,
        'consent_version': 'roster-ai-extraction-v1',
      },
    }, sha256.convert(bytes).toString());
  }
}
