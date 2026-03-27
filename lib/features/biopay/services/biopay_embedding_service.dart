import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/biopay_model_contract.dart';

class BiopayEmbeddingService {
  static const modelAssetPath = BiopayModelContract.modelAssetPath;
  static const modelContractAssetPath = BiopayModelContract.contractAssetPath;
  static const embeddingSize = BiopayModelContract.expectedEmbeddingSize;
  static int get inputWidth => BiopayModelContract.expectedInputShape[1];
  static int get inputHeight => BiopayModelContract.expectedInputShape[2];

  Interpreter? _interpreter;
  Delegate? _delegate;
  String? _initializationError;
  BiopayModelContract? _modelContract;

  bool get isReady => _interpreter != null;
  String? get initializationError => _initializationError;

  Future<bool> isModelAssetAvailable() => _assetExists(modelAssetPath);

  Future<String?> getModelAssetIssue() async {
    final modelBytes = await _loadModelBytes();
    if (modelBytes == null) {
      return 'BioPay face model is not bundled in this build yet. Add mobilefacenet_int8.tflite to assets/models/biopay/.';
    }

    BiopayModelContract contract;
    try {
      contract = await _loadModelContract();
    } on StateError catch (error) {
      return error.message;
    }
    final contractIssue = contract.validateModelBytes(modelBytes);
    if (contractIssue != null) {
      return contractIssue;
    }

    return null;
  }

  Future<bool> ensureInitialized() async {
    if (_interpreter != null) {
      return true;
    }
    if (_initializationError != null) {
      return false;
    }

    final modelBytes = await _loadModelBytes();
    if (modelBytes == null) {
      _initializationError =
          'BioPay model asset is missing at $modelAssetPath. Drop mobilefacenet_int8.tflite into assets/models/biopay/.';
      return false;
    }

    try {
      final contract = await _loadModelContract();
      final contractIssue = contract.validateModelBytes(modelBytes);
      if (contractIssue != null) {
        _initializationError = contractIssue;
        return false;
      }

      await _initialiseWithPlatformAcceleration(modelBytes);
      final interpreterIssue = _validateInterpreterContract(
        contract,
        _interpreter!,
      );
      if (interpreterIssue != null) {
        _initializationError = interpreterIssue;
        dispose();
        return false;
      }
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

  Future<void> _initialiseWithPlatformAcceleration(Uint8List modelBytes) async {
    final attempts = <Future<void> Function()>[
      if (Platform.isAndroid) () => _tryAndroidGpu(modelBytes),
      if (Platform.isAndroid) () => _tryAndroidNnApi(modelBytes),
      if (Platform.isIOS) () => _tryIosCoreMl(modelBytes),
      () => _tryCpuOnly(modelBytes),
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

  Future<void> _tryAndroidGpu(Uint8List modelBytes) async {
    final delegate = GpuDelegateV2();
    final options = InterpreterOptions()
      ..threads = 2
      ..addDelegate(delegate);
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
    _delegate = delegate;
    _interpreter = interpreter;
  }

  Future<void> _tryAndroidNnApi(Uint8List modelBytes) async {
    final options = InterpreterOptions()
      ..threads = 2
      ..useNnApiForAndroid = true;
    _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
  }

  Future<void> _tryIosCoreMl(Uint8List modelBytes) async {
    final delegate = CoreMlDelegate();
    final options = InterpreterOptions()
      ..threads = 2
      ..addDelegate(delegate);
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
    _delegate = delegate;
    _interpreter = interpreter;
  }

  Future<void> _tryCpuOnly(Uint8List modelBytes) async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
  }

  Future<Uint8List?> _loadModelBytes() async {
    try {
      final byteData = await rootBundle.load(modelAssetPath);
      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<BiopayModelContract> _loadModelContract() async {
    final cached = _modelContract;
    if (cached != null) {
      return cached;
    }

    try {
      final source = await rootBundle.loadString(modelContractAssetPath);
      final contract = BiopayModelContract.fromJsonString(source);
      _modelContract = contract;
      return contract;
    } on FlutterError {
      throw StateError(
        'BioPay model contract is missing at $modelContractAssetPath. Run `dart tool/biopay_model_contract.dart --generate` after placing the production model asset.',
      );
    } on FormatException catch (error) {
      throw StateError(
        'BioPay model contract is invalid at $modelContractAssetPath: ${error.message}',
      );
    } on Object catch (error) {
      throw StateError(
        'BioPay model contract could not be loaded from $modelContractAssetPath: $error',
      );
    }
  }

  String? _validateInterpreterContract(
    BiopayModelContract contract,
    Interpreter interpreter,
  ) {
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    return contract.validateTensorMetadata(
      runtimeInputShape: inputTensor.shape,
      runtimeInputType: inputTensor.type.name,
      runtimeOutputShape: outputTensor.shape,
      runtimeOutputType: outputTensor.type.name,
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
