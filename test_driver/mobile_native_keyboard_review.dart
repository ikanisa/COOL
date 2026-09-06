// QA-only host driver. flutter_driver comes from the SDK integration_test.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

const _adb = '/Users/jeanbosco/Library/Android/sdk/platform-tools/adb';
const _serial = 'emulator-5558';
const _avd = 'Collect_Design_Renderer_QA_20260905';
const _cases = [
  {
    'name': 'auth',
    'route': '/auth',
    'signedIn': false,
    'action': 'Send WhatsApp code',
    'input': '788123457',
  },
  {
    'name': 'profile-edit',
    'route': '/settings/profile',
    'action': 'Save',
    'input': '0788123457',
  },
  {
    'name': 'diaspora-profile',
    'route': '/settings/profile',
    'diaspora': true,
    'action': 'Save',
    'input': '000123456780',
  },
  {
    'name': 'profile-momo-code',
    'route': '/settings/profile',
    'tab': 'profile_momo_code_tab',
    'action': 'Save',
    'input': '008000',
  },
  {
    'name': 'contribution',
    'route': '/groups/qa-private-group/contribute',
    'action': 'Continue to MoMo',
    'input': '1234',
    'expectedText': '1,234',
  },
  {
    'name': 'diaspora-contribution',
    'route': '/groups/qa-private-group/contribute',
    'diaspora': true,
    'action': 'Review transfer',
    'input': '12.34',
  },
  {
    'name': 'group-create',
    'route': '/groups/create',
    'action': 'Continue',
    'input': 'Kigali',
  },
  {
    'name': 'group-join',
    'route': '/c/qa-private-group',
    'signedIn': false,
    'action': 'Send WhatsApp code',
    'input': '788123457',
  },
  {'name': 'groups-search', 'route': '/groups', 'input': 'QA'},
];

Future<String> _android(List<String> args) async {
  final result = await Process.run(_adb, ['-s', _serial, ...args]);
  if (result.exitCode != 0) {
    throw StateError('ADB ${args.first}: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

bool _visible(Map<String, dynamic>? rect, Map<String, dynamic> state) {
  if (rect == null) return false;
  return (rect['y'] as num) >= 0 &&
      (rect['x'] as num) >= 0 &&
      (rect['x'] as num) + (rect['width'] as num) <=
          (state['width'] as num) + 1 &&
      (rect['y'] as num) + (rect['height'] as num) <=
          (state['height'] as num) - (state['keyboardInset'] as num) + 1;
}

Future<void> main() async {
  if (!(await _android(['emu', 'avd', 'name'])).startsWith(_avd)) {
    throw StateError('Only the disposable Collect design AVD is authorized.');
  }
  final output = Directory(
    Platform.environment['COLLECT_KEYBOARD_EVIDENCE_DIR'] ??
        '.cache/revolut-design-20260906/native-keyboard',
  );
  output.createSync(recursive: true);
  final original = <String, String>{};
  for (final setting in [
    'font_scale',
    'accelerometer_rotation',
    'user_rotation',
  ]) {
    original[setting] = await _android([
      'shell',
      'settings',
      'get',
      'system',
      setting,
    ]);
  }
  final results = <Map<String, dynamic>>[];
  final driver = await FlutterDriver.connect();
  Future<Map<String, dynamic>> command(
    String name, [
    Map<String, Object>? args,
  ]) async =>
      jsonDecode(
            await driver.runUnsynchronized(
              () => driver.requestData(
                jsonEncode({'command': name, ...?args}),
                timeout: const Duration(seconds: 45),
              ),
            ),
          )
          as Map<String, dynamic>;
  Future<void> screenshot(String filename) async {
    final result = await Process.run(_adb, [
      '-s',
      _serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (result.exitCode != 0) throw StateError('OS screenshot failed');
    File(
      '${output.path}/$filename',
    ).writeAsBytesSync(result.stdout as List<int>);
  }

  void save() => File('${output.path}/report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'platform': 'Android',
      'device': _serial,
      'avd': _avd,
      'input': 'Android input service; Flutter text entry emulation disabled',
      'captures': 'adb exec-out screencap -p; includes the actual OS IME',
      'fixtures_only': true,
      'actions_submitted': false,
      'original_settings': original,
      'status':
          results.isNotEmpty &&
              results.every((r) => (r['failures'] as List).isEmpty)
          ? 'pass'
          : 'fail',
      'results': results,
    }),
  );
  try {
    await _android([
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      '0',
    ]);
    for (final scale in [1, 2]) {
      await _android([
        'shell',
        'settings',
        'put',
        'system',
        'font_scale',
        '$scale',
      ]);
      for (final landscape in [false, true]) {
        await _android([
          'shell',
          'settings',
          'put',
          'system',
          'user_rotation',
          landscape ? '1' : '0',
        ]);
        await Future<void>.delayed(const Duration(seconds: 2));
        for (final scenario in _cases) {
          final filter = Platform.environment['COLLECT_KEYBOARD_CASE'];
          if (filter != null && scenario['name'] != filter) continue;
          final name =
              '${scenario['name']}-${landscape ? 'landscape' : 'portrait'}-${scale * 100}';
          final failures = <String>[];
          final row = <String, dynamic>{
            'name': name,
            'scenario': scenario,
            'font_scale': scale,
            'orientation': landscape ? 'landscape' : 'portrait',
            'failures': failures,
          };
          results.add(row);
          try {
            final opened = await command('open', scenario);
            row['opened'] = opened;
            final expectedRoute = scenario['name'] == 'group-join'
                ? '/auth'
                : scenario['route'];
            if (opened['route'] != expectedRoute) {
              throw StateError(
                'Unexpected route after fixture setup: ${opened['route']}',
              );
            }
            if (scenario['name'] == 'groups-search') {
              final center = await driver.runUnsynchronized(
                () => driver.getCenter(
                  find.byTooltip('Search groups'),
                  timeout: const Duration(seconds: 15),
                ),
              );
              final ratio = opened['devicePixelRatio'] as num;
              await _android([
                'shell',
                'input',
                'tap',
                '${(center.dx * ratio).round()}',
                '${(center.dy * ratio).round()}',
              ]);
            }
            if (scenario['tab'] case final String tab) {
              final finder = find.byValueKey(tab);
              // Reveal the existing profile field first so the lazy list has
              // mounted the preceding switcher at enlarged OS text sizes.
              await command('reveal-field');
              await driver.runUnsynchronized(
                () => driver.scrollIntoView(
                  finder,
                  timeout: const Duration(seconds: 15),
                ),
              );
              final center = await driver.runUnsynchronized(
                () => driver.getCenter(
                  finder,
                  timeout: const Duration(seconds: 15),
                ),
              );
              final ratio = opened['devicePixelRatio'] as num;
              await _android([
                'shell',
                'input',
                'tap',
                '${(center.dx * ratio).round()}',
                '${(center.dy * ratio).round()}',
              ]);
            }
            var before = await command('reveal-field');
            if (before['focused'] == true) {
              // Autofocus can open the IME between measurement and an OS tap.
              await Future<void>.delayed(const Duration(seconds: 1));
              before = await command('reveal-field');
            }
            row['before'] = before;
            final field = before['field'] as Map<String, dynamic>;
            final ratio = before['devicePixelRatio'] as num;
            await _android([
              'shell',
              'input',
              'tap',
              '${((field['x'] + field['width'] / 2) * ratio).round()}',
              '${((field['y'] + field['height'] / 2) * ratio).round()}',
            ]);
            var state = await command('inspect');
            for (
              var attempt = 0;
              (state['keyboardInset'] as num) == 0 && attempt < 15;
              attempt++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              state = await command('inspect');
            }
            // A cold emulator can move the field while the first OS focus
            // event is dispatched. Re-measure and re-tap, then require actual
            // focus and IME visibility before sending any text.
            for (
              var attempt = 0;
              (state['focused'] != true ||
                      (state['keyboardInset'] as num) == 0) &&
                  attempt < 3;
              attempt++
            ) {
              final fresh = await command('reveal-field');
              final rect = fresh['field'] as Map<String, dynamic>;
              await _android([
                'shell',
                'input',
                'tap',
                '${((rect['x'] + rect['width'] / 2) * ratio).round()}',
                '${((rect['y'] + rect['height'] / 2) * ratio).round()}',
              ]);
              await Future<void>.delayed(const Duration(seconds: 1));
              state = await command('inspect');
            }
            if (state['focused'] != true ||
                (state['keyboardInset'] as num) == 0) {
              throw StateError('OS focus and keyboard did not become ready');
            }
            await command('reveal-field');
            // Android does not consistently forward desktop select-all
            // shortcuts to these native input connections. Delete on both
            // sides of the caret through real OS key events, then read back.
            var cleared = await command('inspect');
            for (
              var attempt = 0;
              cleared['inputText'] != '' && attempt < 3;
              attempt++
            ) {
              final length = (cleared['inputText'] as String).length;
              await _android([
                'shell',
                'input',
                'keyevent',
                ...List.filled(length, '67'),
                ...List.filled(length, '112'),
              ]);
              await Future<void>.delayed(const Duration(milliseconds: 700));
              cleared = await command('inspect');
            }
            row['cleared'] = cleared;
            if (cleared['inputText'] != '') {
              throw StateError('OS deletion did not clear the field');
            }
            await _android([
              'shell',
              'input',
              'text',
              (scenario['input'] as String).replaceAll(' ', '%s'),
            ]);
            await Future<void>.delayed(const Duration(milliseconds: 600));
            state = await command('inspect');
            row['focused'] = state;
            if (state['route'] != expectedRoute) {
              failures.add('Typing changed route unexpectedly');
            }
            if (scenario['name'] == 'group-join' &&
                state['pendingGroupSlug'] != 'qa-private-group') {
              failures.add('Invitation intent was lost during sign-in input');
            }
            final ime = await _android(['shell', 'dumpsys', 'input_method']);
            row['ime_visibility'] = ime
                .split('\n')
                .where(
                  (line) =>
                      line.contains('mInputShown=') ||
                      line.contains('mIsInputViewShown='),
                )
                .map((s) => s.trim())
                .toList();
            if ((state['keyboardInset'] as num) <= 0) {
              failures.add('No real keyboard inset');
            }
            if (!ime.contains('mInputShown=true') &&
                !ime.contains('mIsInputViewShown=true')) {
              failures.add('Android IME does not report visible');
            }
            if (state['focused'] != true) failures.add('Field lost focus');
            if (state['fieldHitTestable'] != true) {
              failures.add('Focused field is obscured at its center');
            }
            if (state['inputText'] !=
                (scenario['expectedText'] ?? scenario['input'])) {
              failures.add('OS input did not round-trip exactly');
            }
            if (!_visible(state['editable'] as Map<String, dynamic>?, state)) {
              failures.add(
                'Editable text is clipped behind keyboard or viewport',
              );
            }
            if (((state['width'] as num) > (state['height'] as num)) !=
                landscape) {
              failures.add('Orientation does not match');
            }
            if (scale == 2 && (state['textScaleAt16'] as num) <= 20) {
              failures.add('OS enlarged text did not reach app');
            }
            row['focused_capture'] = '$name-focused.png';
            await screenshot(row['focused_capture'] as String);
            if (scenario['action'] != null) {
              final action = await command('reveal-action');
              row['action'] = action;
              if (!_visible(
                action['action'] as Map<String, dynamic>?,
                action,
              )) {
                failures.add('Action label cannot be scrolled above keyboard');
              }
              if (!_visible(
                action['actionControl'] as Map<String, dynamic>?,
                action,
              )) {
                failures.add('Full action control is clipped');
              }
              if (action['actionHitTestable'] != true) {
                failures.add('Action control is obscured at its center');
              }
              if ((action['keyboardInset'] as num) <= 0) {
                failures.add('Keyboard disappeared before action review');
              }
              row['action_capture'] = '$name-action.png';
              await screenshot(row['action_capture'] as String);
              if ((action['errors'] as List).isNotEmpty) {
                failures.addAll((action['errors'] as List).cast<String>());
              }
            }
            if ((state['errors'] as List).isNotEmpty) {
              failures.addAll((state['errors'] as List).cast<String>());
            }
          } catch (error) {
            failures.add('$error');
          }
          save();
          stdout.writeln(
            '$name: ${failures.isEmpty ? 'PASS' : failures.join('; ')}',
          );
        }
      }
    }
  } finally {
    await driver.close();
    for (final setting in original.entries) {
      await _android([
        'shell',
        'settings',
        setting.value == 'null' ? 'delete' : 'put',
        'system',
        setting.key,
        if (setting.value != 'null') setting.value,
      ]);
    }
    save();
  }
  if (results.any((r) => (r['failures'] as List).isNotEmpty)) exitCode = 1;
}
