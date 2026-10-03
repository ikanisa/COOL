import 'dart:ui';

import 'package:flutter/material.dart';

import '../logging/app_logger.dart';
import 'collect_startup_host.dart';

/// Replaces raw framework/platform reporting with fixed structured events and
/// public recovery copy. The previous handlers are restored only if still ours.
class CollectGlobalErrorHandlers {
  CollectGlobalErrorHandlers({
    required this.diagnostics,
    this.onApplicationFault,
  });

  final CollectDiagnostics diagnostics;
  final VoidCallback? onApplicationFault;
  void Function(FlutterErrorDetails)? _previousFramework;
  bool Function(Object, StackTrace)? _previousPlatform;
  ErrorWidgetBuilder? _previousWidget;
  bool _installed = false;
  bool _faultScheduled = false;

  late final void Function(FlutterErrorDetails) _frameworkHandler = _framework;
  late final bool Function(Object, StackTrace) _platformHandler = _platform;
  late final ErrorWidgetBuilder _widgetHandler = _widget;

  void _framework(FlutterErrorDetails _) {
    diagnostics.record(CollectDiagnosticCode.frameworkFailure);
    _scheduleFault();
  }

  bool _platform(Object _, StackTrace stack) {
    diagnostics.record(CollectDiagnosticCode.platformFailure);
    _scheduleFault();
    return true;
  }

  Widget _widget(FlutterErrorDetails _) => const CollectFatalRecoveryApp();

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFramework = FlutterError.onError;
    _previousPlatform = PlatformDispatcher.instance.onError;
    _previousWidget = ErrorWidget.builder;
    FlutterError.onError = _frameworkHandler;
    PlatformDispatcher.instance.onError = _platformHandler;
    ErrorWidget.builder = _widgetHandler;
  }

  void _scheduleFault() {
    final onFault = onApplicationFault;
    if (onFault == null || _faultScheduled) return;
    _faultScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _faultScheduled = false;
      if (_installed) onFault();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    if (!_installed) return;
    _installed = false;
    if (identical(FlutterError.onError, _frameworkHandler)) {
      FlutterError.onError = _previousFramework;
    }
    if (identical(PlatformDispatcher.instance.onError, _platformHandler)) {
      PlatformDispatcher.instance.onError = _previousPlatform;
    }
    if (identical(ErrorWidget.builder, _widgetHandler)) {
      ErrorWidget.builder = _previousWidget!;
    }
  }
}
