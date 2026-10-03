import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/collect_components.dart';
import 'collect_startup_controller.dart';

/// Draws a recovery surface before beginning asynchronous initialization.
/// The caller owns the controller, including its disposal.
class CollectStartupHost<T> extends StatefulWidget {
  const CollectStartupHost({
    required this.controller,
    required this.application,
    this.admin = false,
    super.key,
  });

  final CollectStartupController<T> controller;
  final Widget Function(T value) application;
  final bool admin;

  @override
  State<CollectStartupHost<T>> createState() => _CollectStartupHostState<T>();
}

class _CollectStartupHostState<T> extends State<CollectStartupHost<T>> {
  @override
  void initState() {
    super.initState();
    _startAfterFrame();
  }

  @override
  void didUpdateWidget(covariant CollectStartupHost<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _startAfterFrame();
    }
  }

  void _startAfterFrame() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(controller, widget.controller)) {
        controller.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.stage == CollectStartupStage.ready) {
        return widget.application(controller.value);
      }
      return _CollectRecoveryApp(
        child: controller.stage == CollectStartupStage.loading
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: CollectSpacing.screenPadding,
                        child: CollectScreenLoadingState(
                          title: widget.admin
                              ? 'Starting Collect Admin'
                              : 'Starting Collect',
                          message: 'Preparing your session.',
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : CollectErrorState(
                title: widget.admin
                    ? 'Collect Admin could not start'
                    : 'Collect could not start',
                message: controller.canRetry
                    ? 'Check your connection and try again.'
                    : 'Restart Collect and try again.',
                onRetry: controller.canRetry ? controller.retry : null,
              ),
      );
    },
  );
}

class CollectFatalRecoveryApp extends StatelessWidget {
  const CollectFatalRecoveryApp({super.key});

  @override
  Widget build(BuildContext context) => const _CollectRecoveryApp(
    child: CollectErrorState(
      title: 'Collect could not continue',
      message: 'Restart Collect and try again.',
    ),
  );
}

class _CollectRecoveryApp extends StatelessWidget {
  const _CollectRecoveryApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Collect',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    highContrastTheme: AppTheme.highContrastLight(),
    highContrastDarkTheme: AppTheme.highContrastDark(),
    home: Scaffold(body: SafeArea(child: child)),
  );
}
