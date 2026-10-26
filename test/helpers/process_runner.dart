import 'dart:convert';
import 'dart:io';

ProcessResult runProcessSync(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool runInShell = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
}) {
  final isRepositoryShellScript =
      (executable.startsWith('./scripts/') ||
          executable.startsWith('scripts/')) &&
      executable.endsWith('.sh');
  return Process.runSync(
    isRepositoryShellScript ? '/bin/bash' : executable,
    isRepositoryShellScript ? [executable, ...arguments] : arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
    stdoutEncoding: stdoutEncoding,
    stderrEncoding: stderrEncoding,
  );
}
