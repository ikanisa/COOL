import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BiopayEmbeddingService {
  static const modelAssetPath =
      'assets/models/biopay/mobilefacenet_int8.tflite';
  static const embeddingSize = 128;
  static const inputWidth = 160;
  static const inputHeight = 160;

  Interpreter? _interpreter;
  Delegate? _delegate;
  String? _initializationError;

  bool get isReady => _interpreter != null;
  String? get initializationError => _initializationError;

  Future<bool> isModelAssetAvailable() => _assetExists(modelAssetPath);

  Future<String?> getModelAssetIssue() async {
    final available = await isModelAssetAvailable();
    if (available) {
      return null;
    }
    return 'BioPay face model is not bundled in this build yet. Add mobilefacenet_int8.tflite to assets/models/biopay/.';
  }

  Future<bool> ensureInitialized() async {
    if (_interpreter != null) {
      return true;
    }
    if (_initializationError != null) {
      return false;
    }

    if (!await _assetExists(modelAssetPath)) {
      _initializationError =
          'BioPay model asset is missing at $modelAssetPath. Drop mobilefacenet_int8.tflite into assets/models/biopay/.';
      return false;
    }

    try {
      await _initialiseWithPlatformAcceleration();
      return _interpreter != null;
    } catch (error) {
      _initializationError = error.toString();
      return false;
    }
  }

  Future<Float32List> embed(Float32List alignedFaceTensor) async {
    final ready = await ensureInitialized();
    if (!ready || _interpreter == null) {
      throw StateError(
        _initializationError ??
            'BioPay embedding model could not be initialized.',
      );
    }

    final input = alignedFaceTensor.toList().reshape<double>([
      1,
      inputWidth,
      inputHeight,
      3,
    ]);
    final output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(embeddingSize, 0),
    );

    _interpreter!.run(input, output);
    return _l2Normalise(Float32List.fromList(output.first));
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

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _delegate?.delete();
    _delegate = null;
  }

  Future<void> _initialiseWithPlatformAcceleration() async {
    final attempts = <Future<void> Function()>[
      if (Platform.isAndroid) _tryAndroidGpu,
      if (Platform.isAndroid) _tryAndroidNnApi,
      if (Platform.isIOS) _tryIosCoreMl,
      _tryCpuOnly,
    ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        await attempt();
        if (_interpreter != null) {
          _initializationError = null;
          return;
        }
      } catch (error) {
        lastError = error;
        _delegate?.delete();
        _delegate = null;
        _interpreter?.close();
        _interpreter = null;
      }
    }

    throw StateError(
      'BioPay embedding model could not be loaded: ${lastError ?? 'unknown error'}',
    );
  }

  Future<void> _tryAndroidGpu() async {
    final delegate = GpuDelegateV2();
    final options = InterpreterOptions()
      ..threads = 2
      ..addDelegate(delegate);
    final interpreter = await Interpreter.fromAsset(
      modelAssetPath,
      options: options,
    );
    _delegate = delegate;
    _interpreter = interpreter;
  }

  Future<void> _tryAndroidNnApi() async {
    final options = InterpreterOptions()
      ..threads = 2
      ..useNnApiForAndroid = true;
    _interpreter = await Interpreter.fromAsset(
      modelAssetPath,
      options: options,
    );
  }

  Future<void> _tryIosCoreMl() async {
    final delegate = CoreMlDelegate();
    final options = InterpreterOptions()
      ..threads = 2
      ..addDelegate(delegate);
    final interpreter = await Interpreter.fromAsset(
      modelAssetPath,
      options: options,
    );
    _delegate = delegate;
    _interpreter = interpreter;
  }

  Future<void> _tryCpuOnly() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      modelAssetPath,
      options: options,
    );
  }

  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

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
