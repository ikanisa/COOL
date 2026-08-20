import 'dart:io';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_spacing.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/app/theme/collect_universal_tokens.dart';
import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('interaction target contract', () {
    test('theme tokens enforce 48 dp actions and 44 dp dense icons', () {
      for (final entry in <String, ThemeData>{
        'light': AppTheme.light(),
        'dark': AppTheme.dark(),
        'high contrast light': AppTheme.highContrastLight(),
        'high contrast dark': AppTheme.highContrastDark(),
      }.entries) {
        final tokens = entry.value.extension<CollectUniversalTokens>()!;
        expect(
          tokens.touchTarget,
          CollectSpacing.target,
          reason: '${entry.key} primary target token',
        );
        expect(
          tokens.iconTarget,
          CollectSpacing.iconTarget,
          reason: '${entry.key} dense icon target token',
        );
        _expectStyleMinimum(
          '${entry.key} filled button',
          entry.value.filledButtonTheme.style,
          CollectSpacing.target,
        );
        _expectStyleMinimum(
          '${entry.key} outlined button',
          entry.value.outlinedButtonTheme.style,
          CollectSpacing.target,
        );
        _expectStyleMinimum(
          '${entry.key} text button',
          entry.value.textButtonTheme.style,
          CollectSpacing.target,
        );
        _expectStyleMinimum(
          '${entry.key} elevated button',
          entry.value.elevatedButtonTheme.style,
          CollectSpacing.target,
        );
        _expectStyleMinimum(
          '${entry.key} icon button',
          entry.value.iconButtonTheme.style,
          CollectSpacing.iconTarget,
        );
      }
    });

    test('runtime source has no literal subminimum button dimensions', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final squareSize = RegExp(
        r'(?:fixedSize|minimumSize)\s*:\s*[^\n]{0,100}?'
        r'Size\.square\(\s*(\d+(?:\.\d+)?)',
      );
      final rectangularSize = RegExp(
        r'(?:fixedSize|minimumSize)\s*:\s*[^\n]{0,100}?'
        r'Size\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)',
      );
      final heightSize = RegExp(
        r'(?:fixedSize|minimumSize)\s*:\s*[^\n]{0,100}?'
        r'Size\.fromHeight\(\s*(\d+(?:\.\d+)?)',
      );

      for (final file in sources) {
        final source = file.readAsStringSync();
        for (final match in squareSize.allMatches(source)) {
          _expectLiteralDimension(file.path, match.group(1)!);
        }
        for (final match in rectangularSize.allMatches(source)) {
          _expectLiteralDimension(file.path, match.group(1)!, allowZero: true);
          _expectLiteralDimension(file.path, match.group(2)!);
        }
        for (final match in heightSize.allMatches(source)) {
          _expectLiteralDimension(file.path, match.group(1)!);
        }
      }
    });

    testWidgets('all 35 member routes expose no sub-44 dp tap target', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final failures = <String>[];
      try {
        for (final route in _memberRoutes) {
          final router = createAppRouter(initialLocation: route);
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('target-contract:$route'),
              overrides: [
                appRouterProvider.overrideWithValue(router),
                collectRepositoryProvider.overrideWith(
                  (ref) => CollectRepository.fixture(),
                ),
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
          await _pumpFrames(tester);
          expect(tester.takeException(), isNull, reason: route);
          failures.addAll(
            _visibleTargetFailures(tester).map((failure) => '$route: $failure'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
        }
        expect(
          failures,
          isEmpty,
          reason:
              'Member routes have subminimum interactive targets:\n'
              '${failures.join('\n')}',
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('public and compact Admin surfaces preserve target floors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final failures = <String>[];
      try {
        tester.view.physicalSize = const Size(390, 10000);
        for (final path in publicWebsitePaths) {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('public-target-contract:$path'),
              child: MaterialApp(
                theme: AppTheme.light(),
                home: path == '/'
                    ? const CollectLandingPage()
                    : CollectPublicPage(data: publicPageForPath(path)),
              ),
            ),
          );
          await tester.pump();
          failures.addAll(
            _visibleTargetFailures(
              tester,
            ).map((failure) => 'public $path: $failure'),
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminAuthGuardProvider.overrideWithValue(
                const AdminAuthGuard(isAuthorized: true),
              ),
              adminIdentityProvider.overrideWith((ref) async => _adminIdentity),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const AdminShell(
                location: '/admin',
                child: Text('Admin overview'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        failures.addAll(
          _visibleTargetFailures(
            tester,
          ).map((failure) => 'compact Admin: $failure'),
        );
        expect(
          failures,
          isEmpty,
          reason:
              'Public/Admin surfaces have subminimum interactive targets:\n'
              '${failures.join('\n')}',
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}

void _expectStyleMinimum(String label, ButtonStyle? style, double expected) {
  final size = style?.minimumSize?.resolve(<WidgetState>{});
  expect(size, isNotNull, reason: '$label must declare a minimum size');
  expect(size!.width, greaterThanOrEqualTo(expected), reason: '$label width');
  expect(size.height, greaterThanOrEqualTo(expected), reason: '$label height');
}

void _expectLiteralDimension(
  String path,
  String raw, {
  bool allowZero = false,
}) {
  final value = double.parse(raw);
  if (allowZero && value == 0) return;
  expect(
    value,
    greaterThanOrEqualTo(CollectSpacing.iconTarget),
    reason: '$path declares a literal interactive dimension of $raw dp',
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index += 1) {
    await tester.pump();
  }
}

List<String> _visibleTargetFailures(WidgetTester tester) {
  final failures = <String>[];
  for (final candidate
      in find.byWidgetPredicate((widget) => widget is IconButton).evaluate()) {
    final button = candidate.widget as IconButton;
    if (button.onPressed == null) continue;
    final size = tester.getSize(find.byWidget(candidate.widget));
    if (size.width + 0.01 < CollectSpacing.iconTarget ||
        size.height + 0.01 < CollectSpacing.iconTarget) {
      failures.add(
        'IconButton ${size.width.toStringAsFixed(1)} x '
        '${size.height.toStringAsFixed(1)}',
      );
    }
  }

  for (final candidate
      in find
          .byWidgetPredicate((widget) => widget is ButtonStyleButton)
          .evaluate()) {
    final button = candidate.widget as ButtonStyleButton;
    if (button.onPressed == null) continue;
    final size = tester.getSize(find.byWidget(candidate.widget));
    if (size.width + 0.01 < CollectSpacing.target ||
        size.height + 0.01 < CollectSpacing.target) {
      failures.add(
        '${candidate.widget.runtimeType} ${size.width.toStringAsFixed(1)} x '
        '${size.height.toStringAsFixed(1)}',
      );
    }
  }

  for (final candidate
      in find.byWidgetPredicate((widget) => widget is InkWell).evaluate()) {
    final inkWell = candidate.widget as InkWell;
    if (inkWell.onTap == null || _hasMaterialControlAncestor(candidate)) {
      continue;
    }
    _recordCustomTargetFailure(tester, candidate, 'InkWell', failures);
  }

  for (final candidate
      in find
          .byWidgetPredicate((widget) => widget is GestureDetector)
          .evaluate()) {
    final detector = candidate.widget as GestureDetector;
    if ((detector.onTap == null && detector.onDoubleTap == null) ||
        _hasMaterialControlAncestor(candidate)) {
      continue;
    }
    _recordCustomTargetFailure(tester, candidate, 'GestureDetector', failures);
  }

  for (final candidate
      in find
          .byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.onTap != null,
          )
          .evaluate()) {
    if (_hasMaterialControlAncestor(candidate)) continue;
    _recordCustomTargetFailure(
      tester,
      candidate,
      'Semantics tap target',
      failures,
    );
  }

  return failures;
}

bool _hasMaterialControlAncestor(Element candidate) {
  var found = false;
  candidate.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    found =
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is RawChip ||
        widget is Switch ||
        widget is Checkbox ||
        widget is Radio ||
        widget is Slider ||
        widget is SegmentedButton ||
        widget is DropdownButton ||
        widget is PopupMenuButton ||
        // Flutter's text-selection handle is a framework-owned 22 dp
        // GestureDetector inside this region. The editable field remains the
        // actual user target and is measured independently by the route test.
        widget is TextFieldTapRegion;
    return !found;
  });
  return found;
}

void _recordCustomTargetFailure(
  WidgetTester tester,
  Element candidate,
  String label,
  List<String> failures,
) {
  final size = tester.getSize(find.byWidget(candidate.widget));
  if (size.width + 0.01 < CollectSpacing.iconTarget ||
      size.height + 0.01 < CollectSpacing.iconTarget) {
    final ancestors = <String>[];
    candidate.visitAncestorElements((ancestor) {
      if (ancestors.length < 16) {
        ancestors.add(ancestor.widget.toStringShort());
      }
      return ancestors.length < 16;
    });
    failures.add(
      '$label ${size.width.toStringAsFixed(1)} x '
      '${size.height.toStringAsFixed(1)} '
      '(widget: ${candidate.widget.runtimeType}; '
      'ancestors: ${ancestors.join(' > ')})',
    );
  }
}

const _memberRoutes = <String>[
  '/',
  '/auth',
  '/settings/profile',
  '/home',
  '/offline',
  '/sync',
  '/groups',
  '/contribute',
  '/activity',
  '/groups/create',
  '/groups/scan',
  '/groups/col-church',
  '/groups/col-church/share',
  '/groups/col-church/invite',
  '/c/st-michel-building-fund',
  '/app',
  '/invite/038491',
  '/share/invalid',
  '/share/expired',
  '/share/expired/request',
  '/groups/col-church/contribute',
  '/groups/col-church/ledger',
  '/groups/col-church/manage',
  '/groups/col-church/profile',
  '/groups/col-church/members',
  '/settings',
  '/settings/notifications',
  '/settings/appearance',
  '/settings/security',
  '/settings/account',
  '/settings/account/delete',
  '/settings/privacy',
  '/settings/help',
  '/settings/legal/privacy',
  '/settings/legal/terms',
];

const _adminIdentity = AdminIdentity(
  userId: 'target-contract-admin',
  displayName: 'Target contract admin',
  roles: ['platform_owner'],
  permissions: [
    'overview.read',
    'collections.read',
    'members.read',
    'payment_intents.read',
    'payment_events.read',
    'ledger.read',
    'receivers.read',
    'sms.metadata.read',
    'audit.read',
    'settings.read',
    'feature_flags.read',
    'system_health.read',
    'admin_users.read',
  ],
);
