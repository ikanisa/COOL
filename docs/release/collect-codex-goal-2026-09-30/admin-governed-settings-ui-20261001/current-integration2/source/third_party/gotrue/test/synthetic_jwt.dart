import 'dart:convert';

// Parsing/expiry fixtures require claims and a structurally valid dummy
// signature. They contain no signed session copied from another environment.
String syntheticJwt(Map<String, dynamic> header, Map<String, dynamic> claims) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(json.encode(value))).replaceAll('=', '');
  return '${encode(header)}.${encode(claims)}.'
      '${base64Url.encode(utf8.encode('synthetic-local-invalid-signature'))}';
}
