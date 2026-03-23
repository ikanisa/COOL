import 'dart:convert';
import 'dart:typed_data';

import 'package:cool_app/features/biopay/models/biopay_model_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiopayModelContract', () {
    test('parses valid JSON and validates matching bytes', () {
      final modelBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final contract = BiopayModelContract.fromJsonString(
        jsonEncode(<String, Object?>{
          'asset_path': BiopayModelContract.modelAssetPath,
          'model_version': 'mobilefacenet_int8_v1',
          'sha256': BiopayModelContract.computeSha256Hex(modelBytes),
          'bytes': modelBytes.lengthInBytes,
          'input_shape': BiopayModelContract.expectedInputShape,
          'input_type': BiopayModelContract.expectedInputType,
          'output_shape': BiopayModelContract.expectedOutputShape,
          'output_type': BiopayModelContract.expectedOutputType,
          'embedding_size': BiopayModelContract.expectedEmbeddingSize,
        }),
      );

      expect(contract.validateStaticExpectations(), isNull);
      expect(contract.validateModelBytes(modelBytes), isNull);
      expect(
        contract.validateTensorMetadata(
          runtimeInputShape: BiopayModelContract.expectedInputShape,
          runtimeInputType: BiopayModelContract.expectedInputType,
          runtimeOutputShape: BiopayModelContract.expectedOutputShape,
          runtimeOutputType: BiopayModelContract.expectedOutputType,
        ),
        isNull,
      );
    });

    test('rejects invalid contract metadata before byte validation', () {
      const contract = BiopayModelContract(
        assetPath: 'assets/models/biopay/wrong.tflite',
        modelVersion: 'mobilefacenet_int8_v1',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        bytes: 4,
        inputShape: <int>[1, 112, 112, 3],
        inputType: 'float32',
        outputShape: <int>[1, 128],
        outputType: 'float32',
        embeddingSize: 128,
      );

      expect(
        contract.validateStaticExpectations(),
        'BioPay model contract asset_path must be assets/models/biopay/mobilefacenet_int8.tflite.',
      );
    });

    test('rejects checksum mismatch for bundled model bytes', () {
      const contract = BiopayModelContract(
        assetPath: BiopayModelContract.modelAssetPath,
        modelVersion: 'mobilefacenet_int8_v1',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        bytes: 4,
        inputShape: BiopayModelContract.expectedInputShape,
        inputType: BiopayModelContract.expectedInputType,
        outputShape: BiopayModelContract.expectedOutputShape,
        outputType: BiopayModelContract.expectedOutputType,
        embeddingSize: BiopayModelContract.expectedEmbeddingSize,
      );

      final issue = contract.validateModelBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      expect(issue, isNotNull);
      expect(issue, contains('BioPay model checksum does not match'));
    });
  });
}
