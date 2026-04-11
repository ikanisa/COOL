import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../models/biopay_model_contract.dart';

class BiopayEmbeddingService {
  static const modelAssetPath = BiopayModelContract.modelAssetPath;
  static const modelContractAssetPath = BiopayModelContract.contractAssetPath;
  static const embeddingSize = BiopayModelContract.expectedEmbeddingSize;
  static int get inputWidth => BiopayModelContract.expectedInputShape[1];
  static int get inputHeight => BiopayModelContract.expectedInputShape[2];

  String? _initializationError;

  bool get isReady => false;
  String? get initializationError =>
      _initializationError ?? _unsupportedMessage;

  static const _unsupportedMessage =
      'BioPay on-device face embeddings are not available in the web build yet.';

  Future<bool> isModelAssetAvailable() async => false;

  Future<String?> getModelAssetIssue() async => _unsupportedMessage;

  Future<bool> ensureInitialized() async {
    _initializationError = _unsupportedMessage;
    return false;
  }

  Future<Float32List> embed(Float32List alignedFaceTensor) async {
    throw StateError(_unsupportedMessage);
  }

  Float32List averageEmbeddings(Iterable<Float32List> embeddings) {
    final list = embeddings.toList(growable: false);
    if (list.isEmpty) {
      throw StateError('At least one BioPay embedding is required.');
    }

    final averaged = Float32List(embeddingSize);
    for (final embedding in list) {
      for (var index = 0; index < embeddingSize; index += 1) {
        averaged[index] += embedding[index];
      }
    }
    for (var index = 0; index < embeddingSize; index += 1) {
      averaged[index] /= list.length;
    }
    return _l2Normalise(averaged);
  }

  void dispose() {}

  Float32List _l2Normalise(Float32List embedding) {
    var normSquared = 0.0;
    for (final value in embedding) {
      normSquared += value * value;
    }
    final norm = math.sqrt(normSquared);
    if (norm == 0) {
      return embedding;
    }
    return Float32List.fromList(
      embedding.map((value) => value / norm).toList(growable: false),
    );
  }
}
