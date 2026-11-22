// Isolated iOS fixture for comparing native framebuffer and UIKit captures.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../test/fixtures/collect_repository_fixture.dart';

GoRouter? _router;
final _errors = <String>[];

void main() {
  if (!kDebugMode ||
      defaultTargetPlatform != TargetPlatform.iOS ||
      !const bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE')) {
    throw StateError('Explicit iOS debug fixture required');
  }
  enableFlutterDriverExtension(
    enableTextEntryEmulation: false,
    handler: _handle,
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _errors.add(details.exceptionAsString());
    previous?.call(details);
  };
  runApp(const MaterialApp(home: SizedBox.shrink()));
}

List<Element> _elements(bool Function(Widget) matches) {
  final found = <Element>[];
  void visit(Element element) {
    if (matches(element.widget)) found.add(element);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Map<String, double> _bounds(Element element) {
  final box = element.findRenderObject()! as RenderBox;
  final offset = box.localToGlobal(Offset.zero);
  return {
    'x': offset.dx,
    'y': offset.dy,
    'width': box.size.width,
    'height': box.size.height,
  };
}

Future<String> _handle(String? message) async {
  final args = jsonDecode(message!) as Map<String, dynamic>;
  if (args['command'] == 'open') {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    runApp(const MaterialApp(home: SizedBox.shrink()));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _router?.dispose();
    _errors.clear();
    final repository = FixtureCollectRepository(
      fixtureNow: DateTime.utc(2026, 9, 2, 10),
    );
    final router = createAppRouter(initialLocation: '/home');
    _router = router;
    final scale = (args['scale'] as num).toDouble();
    runApp(
      MediaQuery(
        data:
            MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first,
            ).copyWith(
              textScaler: TextScaler.linear(scale),
              highContrast: scale > 1,
              disableAnimations: scale > 1,
              accessibleNavigation: scale > 1,
            ),
        child: ProviderScope(
          key: UniqueKey(),
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
            collectThemeModeProvider.overrideWith(
              (ref) => CollectThemeModeController(
                initialMode: args['theme'] == 'light'
                    ? ThemeMode.light
                    : ThemeMode.dark,
                loadPersistedMode: false,
              ),
            ),
          ],
          child: const CollectApp(),
        ),
      ),
    );
  } else if (args['command'] == 'profile') {
    _router!.go('/settings/profile');
  } else if (args['command'] != 'inspect' && args['command'] != 'snapshot') {
    throw ArgumentError('Unknown fixture command');
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  final items = <Map<String, Object>>[];
  for (final name in ['home', 'groups', 'activity', 'profile']) {
    final nodes = _elements((w) => w.key == ValueKey('collect-nav-$name'));
    if (nodes.length != 1) {
      throw StateError('Expected one $name navigation item');
    }
    Element? icon;
    void visit(Element child) {
      if (child.widget is Icon) icon = child;
      child.visitChildren(visit);
    }

    nodes.single.visitChildren(visit);
    if (icon == null) throw StateError('Missing $name icon');
    items.add({
      'name': name,
      'bounds': _bounds(nodes.single),
      'icon': _bounds(icon!),
    });
  }
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final result = <String, Object?>{
    'route': _router!.routeInformationProvider.value.uri.toString(),
    'devicePixelRatio': view.devicePixelRatio,
    'navigation': items,
    'errors': List<String>.of(_errors),
  };
  if (args['command'] == 'snapshot') {
    final bytes = await const MethodChannel(
      'plugins.flutter.io/integration_test',
    ).invokeMethod<List<dynamic>>('captureScreenshot', {'name': args['name']});
    result['png'] = base64Encode(bytes!.cast<int>());
  }
  return jsonEncode(result);
}
