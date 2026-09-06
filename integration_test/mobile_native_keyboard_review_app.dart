// flutter_driver is supplied by the SDK integration_test dependency. This file
// is a guarded fixture entry point and is never imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../test/fixtures/collect_repository_fixture.dart';

GoRouter? _router;
String? _action;
final _errors = <String>[];
PendingSharedGroupIntentStore? _intentStore;

class _FixtureIntentPreferences implements PendingSharedGroupIntentPreferences {
  final _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];
  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
  @override
  Future<void> remove(String key) async => _values.remove(key);
}

/// Read-only geometry and fixture navigation are exposed to the local driver.
/// Field focus and text input come from the platform input service, with no
/// mocked MediaQuery, keyboard, or text scale. Actions are never submitted.
void main() {
  enableFlutterDriverExtension(
    enableTextEntryEmulation: false,
    handler: _handle,
  );
  final androidFixture =
      defaultTargetPlatform == TargetPlatform.android && appFlavor == 'dev';
  final iosFixture =
      defaultTargetPlatform == TargetPlatform.iOS &&
      const bool.fromEnvironment('COLLECT_IOS_KEYBOARD_REVIEW');
  if (!kDebugMode ||
      !(androidFixture || iosFixture) ||
      !const bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE')) {
    throw StateError(
      'Native keyboard review requires an explicit platform debug fixture.',
    );
  }
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    _errors.add(details.exceptionAsString());
    reportError?.call(details);
  };
  runApp(const MaterialApp(home: SizedBox.shrink()));
}

List<Element> _elementsWhere(bool Function(Widget) predicate) {
  final result = <Element>[];
  void visit(Element element) {
    if (predicate(element.widget)) result.add(element);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

Element? _field() {
  final fields = _elementsWhere((widget) => widget is TextField);
  return fields.isEmpty ? null : fields.first;
}

Element? _actionElement() {
  if (_action == null) return null;
  final labels = _elementsWhere(
    (widget) => widget is Text && widget.data == _action,
  );
  return labels.isEmpty ? null : labels.first;
}

Element? _actionControl() {
  Element? control;
  _actionElement()?.visitAncestorElements((element) {
    if (element.widget is ButtonStyleButton) {
      control = element;
      return false;
    }
    return true;
  });
  return control;
}

bool _hitTestable(Element? element) {
  final box = element?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return false;
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(
    result,
    box.localToGlobal(box.size.center(Offset.zero)),
    WidgetsBinding.instance.platformDispatcher.views.first.viewId,
  );
  return result.path.any((entry) => entry.target == box);
}

Map<String, double>? _bounds(Element? element) {
  final box = element?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return {
    'x': topLeft.dx,
    'y': topLeft.dy,
    'width': box.size.width,
    'height': box.size.height,
  };
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<String> _handle(String? message) async {
  final command = jsonDecode(message!) as Map<String, dynamic>;
  switch (command['command']) {
    case 'open':
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      runApp(const MaterialApp(home: SizedBox.shrink()));
      await _settle();
      _router?.dispose();
      _errors.clear();
      // Each synthetic scenario has independent intent storage. In particular,
      // the invitation case must not redirect the following signed-in case.
      final intentStore = PendingSharedGroupIntentStore(
        preferences: _FixtureIntentPreferences(),
      );
      _intentStore = intentStore;
      _action = command['action'] as String?;
      final repository = FixtureCollectRepository(
        seeded: command['signedIn'] != false,
        fixtureNow: DateTime.utc(2026, 9, 2, 10),
        profileOverride: command['diaspora'] == true
            ? const CollectProfile(
                id: 'local-user',
                publicId: '038491',
                whatsappPhone: '+250788123456',
                countryCode: 'DE',
                currencyCode: 'EUR',
                revolutAccount: '000123456789',
              )
            : null,
      );
      final router = createAppRouter(
        initialLocation: command['route'] as String,
        routeRedirect: (state) => collectAuthenticationRedirect(
          uri: state.uri,
          hasProfile: repository.state.currentProfile != null,
          isLoading: repository.state.isLoading,
        ),
      );
      _router = router;
      runApp(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            pendingSharedGroupIntentStoreProvider.overrideWithValue(
              intentStore,
            ),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
            collectThemeModeProvider.overrideWith(
              (ref) => CollectThemeModeController(
                initialMode: ThemeMode.dark,
                loadPersistedMode: false,
              ),
            ),
          ],
          child: const CollectApp(),
        ),
      );
      await _settle();
    case 'reveal-field':
      // Forms may lazily build fields below the initial viewport.
      for (var step = 0; _field() == null && step < 20; step++) {
        for (final element in _elementsWhere((w) => w is Scrollable)) {
          final state = (element as StatefulElement).state as ScrollableState;
          final position = state.position;
          if (position.axis == Axis.vertical && position.hasContentDimensions) {
            position.jumpTo(
              (position.pixels + 120).clamp(0, position.maxScrollExtent),
            );
          }
        }
        await _settle();
      }
      if (_field() == null) throw StateError('No input field in fixture');
      await Scrollable.ensureVisible(_field()!, alignment: 0.5);
      await _settle();
    case 'reveal-action':
      final target = _actionControl();
      if (target == null) throw StateError('No action label: $_action');
      await Scrollable.ensureVisible(target, alignment: 0.5);
      await _settle();
    case 'inspect':
      break;
    default:
      throw ArgumentError('Unknown review command');
  }
  final field = _field();
  final editable = _elementsWhere((w) => w is EditableText);
  final input = editable.isEmpty ? null : editable.first.widget as EditableText;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final media = field == null ? null : MediaQuery.of(field);
  return jsonEncode({
    'route': _router?.routeInformationProvider.value.uri.toString(),
    'pendingGroupSlug': await _intentStore?.readSlug(),
    'devicePixelRatio': view.devicePixelRatio,
    'width': view.physicalSize.width / view.devicePixelRatio,
    'height': view.physicalSize.height / view.devicePixelRatio,
    'keyboardInset': view.viewInsets.bottom / view.devicePixelRatio,
    'textScaleAt16': media?.textScaler.scale(16),
    'field': _bounds(field),
    'editable': _bounds(editable.isEmpty ? null : editable.first),
    'focused': input?.focusNode.hasFocus ?? false,
    'fieldHitTestable': _hitTestable(field),
    'inputText': input?.controller.text,
    'action': _bounds(_actionElement()),
    'actionControl': _bounds(_actionControl()),
    'actionHitTestable': _hitTestable(_actionControl()),
    'actionEnabled': (_actionControl()?.widget as ButtonStyleButton?)?.enabled,
    'errors': List<String>.of(_errors),
  });
}
