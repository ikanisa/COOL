import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

class BiopayModelContract {
  const BiopayModelContract({
    required this.assetPath,
    required this.modelVersion,
    required this.sha256,
    required this.bytes,
    required this.inputShape,
    required this.inputType,
    required this.outputShape,
    required this.outputType,
    required this.embeddingSize,
    this.generatedAt,
  });

  static const modelAssetPath =
      'assets/models/biopay/mobilefacenet_int8.tflite';
  static const contractAssetPath =
      'assets/models/biopay/mobilefacenet_int8.contract.json';
  static const defaultModelVersion = 'mobilefacenet_int8_v1';
  static const expectedInputShape = <int>[1, 160, 160, 3];
  static const expectedOutputShape = <int>[1, 128];
  static const expectedInputType = 'float32';
  static const expectedOutputType = 'float32';
  static const expectedEmbeddingSize = 128;

  final String assetPath;
  final String modelVersion;
  final String sha256;
  final int bytes;
  final List<int> inputShape;
  final String inputType;
  final List<int> outputShape;
  final String outputType;
  final int embeddingSize;
  final String? generatedAt;

  factory BiopayModelContract.fromJson(Map<String, Object?> json) {
    return BiopayModelContract(
      assetPath: _readRequiredString(json, 'asset_path'),
      modelVersion: _readRequiredString(json, 'model_version'),
      sha256: _readRequiredString(json, 'sha256'),
      bytes: _readRequiredInt(json, 'bytes'),
      inputShape: _readRequiredIntList(json, 'input_shape'),
      inputType: _readRequiredString(json, 'input_type'),
      outputShape: _readRequiredIntList(json, 'output_shape'),
      outputType: _readRequiredString(json, 'output_type'),
      embeddingSize: _readRequiredInt(json, 'embedding_size'),
      generatedAt: _readOptionalString(json, 'generated_at'),
    );
  }

  factory BiopayModelContract.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'BioPay model contract must decode to a JSON object.',
      );
    }
    return BiopayModelContract.fromJson(Map<String, Object?>.from(decoded));
  }

  static String computeSha256Hex(Uint8List bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'asset_path': assetPath,
      'model_version': modelVersion,
      'sha256': sha256,
      'bytes': bytes,
      'input_shape': inputShape,
      'input_type': inputType,
      'output_shape': outputShape,
      'output_type': outputType,
      'embedding_size': embeddingSize,
      if (generatedAt != null) 'generated_at': generatedAt,
    };
  }

  String? validateStaticExpectations() {
    if (assetPath != modelAssetPath) {
      return 'BioPay model contract asset_path must be $modelAssetPath.';
    }
    if (modelVersion.trim().isEmpty) {
      return 'BioPay model contract must declare a non-empty model_version.';
    }
    if (!_looksLikeSha256(sha256)) {
      return 'BioPay model contract must declare a 64-character lowercase sha256.';
    }
    if (bytes <= 0) {
      return 'BioPay model contract bytes must be greater than 0.';
    }
    if (!_matchesShape(inputShape, expectedInputShape)) {
      return 'BioPay model contract input_shape must be ${expectedInputShape.join("x")}.';
    }
    if (inputType != expectedInputType) {
      return 'BioPay model contract input_type must be $expectedInputType.';
    }
    if (!_matchesShape(outputShape, expectedOutputShape)) {
      return 'BioPay model contract output_shape must be ${expectedOutputShape.join("x")}.';
    }
    if (outputType != expectedOutputType) {
      return 'BioPay model contract output_type must be $expectedOutputType.';
    }
    if (embeddingSize != expectedEmbeddingSize) {
      return 'BioPay model contract embedding_size must be $expectedEmbeddingSize.';
    }
    return null;
  }

  String? validateModelBytes(Uint8List modelBytes) {
    final staticIssue = validateStaticExpectations();
    if (staticIssue != null) {
      return staticIssue;
    }

    if (modelBytes.lengthInBytes != bytes) {
      return 'BioPay model bytes do not match the contract. Expected $bytes bytes, found ${modelBytes.lengthInBytes}.';
    }

    final digest = computeSha256Hex(modelBytes);
    if (digest != sha256) {
      return 'BioPay model checksum does not match the contract. Expected $sha256, found $digest.';
    }

    return null;
  }

  String? validateTensorMetadata({
    required List<int> runtimeInputShape,
    required String runtimeInputType,
    required List<int> runtimeOutputShape,
    required String runtimeOutputType,
  }) {
    final staticIssue = validateStaticExpectations();
    if (staticIssue != null) {
      return staticIssue;
    }
    if (!_matchesShape(runtimeInputShape, inputShape)) {
      return 'BioPay model input tensor shape does not match the contract. Expected ${inputShape.join("x")}, found ${runtimeInputShape.join("x")}.';
    }
    if (runtimeInputType != inputType) {
      return 'BioPay model input tensor type does not match the contract. Expected $inputType, found $runtimeInputType.';
    }
    if (!_matchesShape(runtimeOutputShape, outputShape)) {
      return 'BioPay model output tensor shape does not match the contract. Expected ${outputShape.join("x")}, found ${runtimeOutputShape.join("x")}.';
    }
    if (runtimeOutputType != outputType) {
      return 'BioPay model output tensor type does not match the contract. Expected $outputType, found $runtimeOutputType.';
    }
    return null;
  }

  static String _readRequiredString(Map<String, Object?> json, String key) {
    final value = _readOptionalString(json, key);
    if (value == null) {
      throw FormatException('Missing BioPay model contract field "$key".');
    }
    return value;
  }

  static String? _readOptionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int _readRequiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException(
      'Missing BioPay model contract integer field "$key".',
    );
  }

  static List<int> _readRequiredIntList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List) {
      throw FormatException('Missing BioPay model contract list field "$key".');
    }

    return value
        .map((entry) {
          if (entry is int) {
            return entry;
          }
          if (entry is num) {
            return entry.toInt();
          }
          throw FormatException(
            'BioPay model contract field "$key" must contain integers only.',
          );
        })
        .toList(growable: false);
  }

  static bool _matchesShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  static bool _looksLikeSha256(String value) {
    final digest = value.trim();
    if (digest.length != 64) {
      return false;
    }
    final pattern = RegExp(r'^[0-9a-f]{64}$');
    return pattern.hasMatch(digest);
  }
}
