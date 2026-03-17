import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Dio [Interceptor] that automatically creates Firebase Performance
/// HTTP metric traces for every network request.
///
/// Enable/disable via [FirebasePerformance.setPerformanceCollectionEnabled].
/// In debug mode, this interceptor still creates metric objects but
/// Performance collection is disabled per [PerformanceService.initialize].
class PerformanceDioInterceptor extends Interceptor {
  PerformanceDioInterceptor({FirebasePerformance? performance})
    : _performance = performance ?? FirebasePerformance.instance;

  final FirebasePerformance _performance;

  // Store metric in request extras so onResponse/onError can retrieve it.
  static const _metricKey = '_fbPerfHttpMetric';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final url = options.uri;
      final method = _httpMethod(options.method);
      final metric = _performance.newHttpMetric(url.toString(), method);
      metric.start();

      // Attach the metric to the request for later retrieval.
      options.extra[_metricKey] = metric;
    } catch (e) {
      debugPrint('[PerfDio] Failed to start metric: $e');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _stopMetric(
      response.requestOptions,
      responseCode: response.statusCode,
      responseContentType: response.headers['content-type']?.first,
      responsePayloadSize: _responseSize(response),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _stopMetric(err.requestOptions, responseCode: err.response?.statusCode);
    handler.next(err);
  }

  void _stopMetric(
    RequestOptions options, {
    int? responseCode,
    String? responseContentType,
    int? responsePayloadSize,
  }) {
    try {
      final metric = options.extra[_metricKey] as HttpMetric?;
      if (metric == null) {
        return;
      }

      if (responseCode != null) {
        metric.httpResponseCode = responseCode;
      }
      if (responseContentType != null) {
        metric.responseContentType = responseContentType;
      }
      if (responsePayloadSize != null) {
        metric.responsePayloadSize = responsePayloadSize;
      }

      // Request payload size (if applicable).
      final requestData = options.data;
      if (requestData is String) {
        metric.requestPayloadSize = requestData.length;
      }

      metric.stop();
    } catch (e) {
      debugPrint('[PerfDio] Failed to stop metric: $e');
    }
  }

  int? _responseSize(Response<dynamic> response) {
    final data = response.data;
    if (data is String) {
      return data.length;
    }
    // For JSON or other types, fall back to content-length header.
    final contentLength = response.headers['content-length']?.first;
    if (contentLength != null) {
      return int.tryParse(contentLength);
    }
    return null;
  }

  HttpMethod _httpMethod(String method) {
    return switch (method.toUpperCase()) {
      'GET' => HttpMethod.Get,
      'POST' => HttpMethod.Post,
      'PUT' => HttpMethod.Put,
      'DELETE' => HttpMethod.Delete,
      'PATCH' => HttpMethod.Patch,
      'OPTIONS' => HttpMethod.Options,
      _ => HttpMethod.Get,
    };
  }
}
