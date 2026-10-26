import 'dart:convert';

// Parsing/expiry fixtures require claims and a structurally valid dummy
// signature. They contain no signed session copied from another environment.
String syntheticJwt(Map<String, dynamic> header, Map<String, dynamic> claims) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(json.encode(value))).replaceAll('=', '');
  return '${encode(header)}.${encode(claims)}.'
      '${base64Url.encode(utf8.encode('synthetic-local-invalid-signature'))}';
}

// Structurally valid, deliberately unsigned by the real service. Only use in
// local MockClient/recoverSession fixtures. Server rejection tests remain real.
String syntheticMemberAccessToken(String userId) => syntheticJwt(
  {'alg': 'HS256', 'typ': 'JWT'},
  {
    'sub': userId,
    'session_id': 'synthetic-member-$userId',
    'role': 'authenticated',
    'surface': 'member',
    'exp': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
  },
);
