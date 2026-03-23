import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cool_app/features/biopay/models/biopay_model_contract.dart';

Future<void> main(List<String> args) async {
  try {
    final generate = args.contains('--generate');
    final check = args.contains('--check') || !generate;

    if (args.any((arg) => arg == '--help' || arg == '-h')) {
      _printUsage();
      exit(0);
    }

    final root = Directory.current;
    final modelFile = File(
      '${root.path}/${BiopayModelContract.modelAssetPath}',
    );
    final contractFile = File(
      '${root.path}/${BiopayModelContract.contractAssetPath}',
    );

    if (generate) {
      final generated = await _generateContract(
        modelFile: modelFile,
        contractFile: contractFile,
        existingContract: await _tryReadExistingContract(contractFile),
      );
      stdout.writeln(
        'Wrote BioPay model contract to ${contractFile.path} for ${generated.modelVersion}.',
      );
    }

    if (check) {
      final issues = await _collectIssues(
        modelFile: modelFile,
        contractFile: contractFile,
      );
      if (issues.isNotEmpty) {
        stderr.writeln('BioPay model contract check failed:');
        for (final issue in issues) {
          stderr.writeln('- $issue');
        }
        stderr.writeln(
          'Run `dart tool/biopay_model_contract.dart --generate` after placing the production model asset.',
        );
        exit(1);
      }

      final contract = BiopayModelContract.fromJsonString(
        await contractFile.readAsString(),
      );
      stdout.writeln(
        'BioPay model contract OK: ${contract.modelVersion} ${contract.sha256} (${contract.bytes} bytes)',
      );
    }
  } on ExitError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  } catch (error) {
    stderr.writeln('BioPay model contract tool failed: $error');
    exit(1);
  }
}

Future<BiopayModelContract?> _tryReadExistingContract(File contractFile) async {
  if (!contractFile.existsSync()) {
    return null;
  }

  try {
    return BiopayModelContract.fromJsonString(
      await contractFile.readAsString(),
    );
  } catch (_) {
    return null;
  }
}

Future<BiopayModelContract> _generateContract({
  required File modelFile,
  required File contractFile,
  required BiopayModelContract? existingContract,
}) async {
  if (!modelFile.existsSync()) {
    throw ExitError(
      'BioPay model asset is missing at ${modelFile.path}. '
      'Place mobilefacenet_int8.tflite in assets/models/biopay/ before generating the contract.',
    );
  }

  final modelBytes = await modelFile.readAsBytes();
  final modelVersion =
      existingContract?.modelVersion ?? BiopayModelContract.defaultModelVersion;
  final contract = BiopayModelContract(
    assetPath: BiopayModelContract.modelAssetPath,
    modelVersion: modelVersion,
    sha256: BiopayModelContract.computeSha256Hex(modelBytes),
    bytes: modelBytes.lengthInBytes,
    inputShape: BiopayModelContract.expectedInputShape,
    inputType: BiopayModelContract.expectedInputType,
    outputShape: BiopayModelContract.expectedOutputShape,
    outputType: BiopayModelContract.expectedOutputType,
    embeddingSize: BiopayModelContract.expectedEmbeddingSize,
    generatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  const encoder = JsonEncoder.withIndent('  ');
  final payload = '${encoder.convert(contract.toJson())}\n';
  await contractFile.writeAsString(payload);
  return contract;
}

Future<List<String>> _collectIssues({
  required File modelFile,
  required File contractFile,
}) async {
  final issues = <String>[];
  final modelExists = modelFile.existsSync();
  final contractExists = contractFile.existsSync();

  if (!modelExists) {
    issues.add(
      'BioPay model asset is missing at ${BiopayModelContract.modelAssetPath}.',
    );
  }
  if (!contractExists) {
    issues.add(
      'BioPay model contract is missing at ${BiopayModelContract.contractAssetPath}.',
    );
    return issues;
  }

  BiopayModelContract contract;
  try {
    contract = BiopayModelContract.fromJsonString(
      await contractFile.readAsString(),
    );
  } on FormatException catch (error) {
    issues.add('BioPay model contract JSON is invalid: ${error.message}');
    return issues;
  }

  final staticIssue = contract.validateStaticExpectations();
  if (staticIssue != null) {
    issues.add(staticIssue);
  }

  if (modelExists) {
    final modelBytes = await modelFile.readAsBytes();
    final bytesIssue = contract.validateModelBytes(
      Uint8List.fromList(modelBytes),
    );
    if (bytesIssue != null) {
      issues.add(bytesIssue);
    }
  }

  return issues;
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart tool/biopay_model_contract.dart [--generate] [--check]',
  );
  stdout.writeln(
    '--generate  Write assets/models/biopay/mobilefacenet_int8.contract.json from the bundled model asset.',
  );
  stdout.writeln(
    '--check     Validate that the bundled model asset and contract are present and consistent.',
  );
}

class ExitError implements Exception {
  const ExitError(this.message);

  final String message;

  @override
  String toString() => message;
}
