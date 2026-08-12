import '../../app/env/app_env.dart';

Uri collectPublicOrigin(AppEnv env) {
  final configured = Uri.tryParse(env.publicUrl.trim());
  if (configured != null &&
      configured.scheme.toLowerCase() == 'https' &&
      configured.host.isNotEmpty &&
      configured.userInfo.isEmpty &&
      !configured.hasQuery &&
      !configured.hasFragment) {
    return configured.replace(
      scheme: 'https',
      path: configured.path.replaceFirst(RegExp(r'/+$'), ''),
    );
  }
  return Uri.parse(defaultCollectPublicUrl);
}

String collectPublicLink(AppEnv env, Iterable<String> pathSegments) {
  final origin = collectPublicOrigin(env);
  final prefix = origin.pathSegments.where((segment) => segment.isNotEmpty);
  return origin.replace(pathSegments: [...prefix, ...pathSegments]).toString();
}
