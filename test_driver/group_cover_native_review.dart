// QA-only host driver; real Android keyboard, synthetic repository.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

const _adb = '/Users/jeanbosco/Library/Android/sdk/platform-tools/adb';
const _serial = 'emulator-5558';

Future<String> android(List<String> args) async {
  final result = await Process.run(_adb, ['-s', _serial, ...args]);
  if (result.exitCode != 0) throw StateError('${args.first}: ${result.stderr}');
  return (result.stdout as String).trim();
}

Future<void> main() async {
  if (!(await android([
    'emu',
    'avd',
    'name',
  ])).startsWith('Collect_Design_Renderer_QA_20260905')) {
    throw StateError('Only the disposable Collect design AVD is authorized.');
  }
  final out = Directory(
    Platform.environment['COLLECT_COVER_NATIVE_EVIDENCE'] ??
        '.cache/group-cover-integration/native',
  );
  out.createSync(recursive: true);
  final original = <String, String>{};
  for (final setting in [
    'font_scale',
    'accelerometer_rotation',
    'user_rotation',
  ]) {
    original[setting] = await android([
      'shell',
      'settings',
      'get',
      'system',
      setting,
    ]);
  }
  final driver = await FlutterDriver.connect();
  final originalHandwriting = await android([
    'shell',
    'settings',
    'get',
    'secure',
    'stylus_handwriting_enabled',
  ]);
  final cases = <Map<String, dynamic>>[];
  String? failure;
  Future<void> tap(SerializableFinder finder) => driver.runUnsynchronized(
    () => driver.tap(finder, timeout: const Duration(seconds: 60)),
  );
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 700));
  Future<Map<String, dynamic>> inspect() async =>
      jsonDecode(
            await driver.runUnsynchronized(() => driver.requestData('inspect')),
          )
          as Map<String, dynamic>;
  Future<void> capture(String name) async {
    final result = await Process.run(_adb, [
      '-s',
      _serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (result.exitCode != 0) throw StateError('OS capture failed');
    File('${out.path}/$name.png').writeAsBytesSync(result.stdout as List<int>);
  }

  Future<void> tapVisiblePhoto(String assetId) async {
    final option = find.byValueKey('group-photo-$assetId');
    final scroll = find.byValueKey('group-photo-scroll');
    final photoTop = await driver.runUnsynchronized(
      () => driver.getTopLeft(option),
    );
    final photoBottom = await driver.runUnsynchronized(
      () => driver.getBottomRight(option),
    );
    final listTop = await driver.runUnsynchronized(
      () => driver.getTopLeft(scroll),
    );
    final listBottom = await driver.runUnsynchronized(
      () => driver.getBottomRight(scroll),
    );
    // Accessibility can merge a sparse row into a wider node. Use the actual
    // keyed InkWell bounds and its visible viewport intersection, then send
    // a real Android input event. A tall landscape image need not fit whole.
    final top = photoTop.dy > listTop.dy ? photoTop.dy : listTop.dy;
    final bottom = photoBottom.dy < listBottom.dy
        ? photoBottom.dy
        : listBottom.dy;
    if (bottom <= top) throw StateError('Photo has no visible tap area');
    final viewport = await inspect();
    final logicalShort =
        (viewport['width'] as num) < (viewport['height'] as num)
        ? viewport['width'] as num
        : viewport['height'] as num;
    final display = await android(['shell', 'wm', 'size']);
    final size = RegExp(r'(\d+)x(\d+)').allMatches(display).last;
    final x = int.parse(size.group(1)!);
    final y = int.parse(size.group(2)!);
    final ratio = (x < y ? x : y) / logicalShort;
    await android([
      'shell',
      'input',
      'tap',
      '${((photoTop.dx + photoBottom.dx) / 2 * ratio).round()}',
      '${((top + bottom) / 2 * ratio).round()}',
    ]);
    await settle();
  }

  String? image(Map<String, dynamic> state) =>
      ((state['groups'] as List).first as Map)['image'] as String?;
  void require(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  try {
    final installedPath = (await android([
      'shell',
      'pm',
      'path',
      'app.cool.mobile.dev',
    ])).split('package:').last.trim();
    final installedHash = (await android([
      'shell',
      'sha256sum',
      installedPath,
    ])).split(RegExp(r'\s+')).first;
    File('${out.path}/installed-apk-readback.json').writeAsStringSync(
      jsonEncode({
        'package': 'app.cool.mobile.dev',
        'installed_apk_sha256': installedHash,
        'method': 'Android sha256sum of installed base APK',
      }),
    );
    await android([
      'shell',
      'settings',
      'put',
      'secure',
      'stylus_handwriting_enabled',
      '0',
    ]);
    await android([
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      '0',
    ]);
    for (final scale in [1, 2]) {
      await android([
        'shell',
        'settings',
        'put',
        'system',
        'font_scale',
        '$scale',
      ]);
      for (final landscape in [false, true]) {
        await android([
          'shell',
          'settings',
          'put',
          'system',
          'user_rotation',
          landscape ? '1' : '0',
        ]);
        await Future<void>.delayed(const Duration(seconds: 2));
        final name =
            'photo-${landscape ? 'landscape' : 'portrait'}-${scale * 100}';
        await tap(find.text('Edit group photo'));
        await settle();
        await tap(find.byTooltip('Upload image'));
        await settle();
        // Use the actual Android accessibility tree to focus the IME, after
        // the modal transition. Synthetic Flutter taps do not establish the
        // Android served-view focus reliably during that transition.
        String? fieldNode;
        for (var attempt = 0; attempt < 10; attempt++) {
          final tree = await android([
            'exec-out',
            'uiautomator',
            'dump',
            '/dev/tty',
          ]);
          File('${out.path}/$name-field.xml').writeAsStringSync(tree);
          final fields = RegExp(
            r'<node\b[^>]*class="android.widget.EditText"[^>]*>',
          ).allMatches(tree).map((m) => m.group(0)!).toList();
          if (fields.isNotEmpty) {
            fieldNode = fields.last;
            break;
          }
          await settle();
        }
        if (fieldNode == null) {
          await capture('$name-missing-field');
          throw StateError('Photo search has no Android input node');
        }
        final bounds = RegExp(
          r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        ).firstMatch(fieldNode)!;
        final xy = [for (var n = 1; n <= 4; n++) int.parse(bounds.group(n)!)];
        await android([
          'shell',
          'input',
          'tap',
          '${(xy[0] + xy[2]) ~/ 2}',
          '${(xy[1] + xy[3]) ~/ 2}',
        ]);
        await settle();
        for (var attempt = 0; attempt < 10; attempt++) {
          if (((await inspect())['keyboardInset'] as num) > 0) break;
          await settle();
        }
        var expectedQuery = '';
        for (final character in 'gusaba'.split('')) {
          await android(['shell', 'input', 'text', character]);
          expectedQuery += character;
          var received = false;
          for (var attempt = 0; attempt < 20; attempt++) {
            await settle();
            if (((await inspect())['fields'] as List).contains(expectedQuery)) {
              received = true;
              break;
            }
          }
          require(
            received,
            'Native character did not round-trip: $expectedQuery',
          );
        }
        final focused = await inspect();
        File(
          '${out.path}/$name-focused.json',
        ).writeAsStringSync(jsonEncode(focused));
        await capture('$name-keyboard');
        require(
          (focused['fields'] as List).contains('gusaba'),
          'Native text did not round-trip',
        );
        require(
          (focused['keyboardInset'] as num) > 0,
          'Missing real keyboard inset',
        );
        final ime = await android(['shell', 'dumpsys', 'input_method']);
        require(
          ime.contains('mInputShown=true') ||
              ime.contains('mIsInputViewShown=true'),
          'Android IME is not visible',
        );
        require(
          ((focused['width'] as num) > (focused['height'] as num)) == landscape,
          'Wrong orientation',
        );
        require(
          (focused['errors'] as List).isEmpty,
          'Flutter errors: ${focused['errors']}',
        );
        await capture('$name-keyboard');
        await android(['shell', 'input', 'keyevent', '4']);
        await settle();
        final option = find.byValueKey(
          'group-photo-rw-10-gusaba-gukwa-gathering',
        );
        await driver.runUnsynchronized(
          () => driver.scrollUntilVisible(
            find.byValueKey('group-photo-scroll'),
            option,
            dyScroll: -130,
          ),
        );
        await tapVisiblePhoto('rw-10-gusaba-gukwa-gathering');
        await capture('$name-selected');
        await tap(find.text('Use photo'));
        await driver.runUnsynchronized(
          () => driver.scrollIntoView(find.text('Save')),
        );
        await capture('$name-ready-to-save');
        await tap(find.text('Save'));
        await settle();
        final saved = await inspect();
        require(
          image(saved) == 'collect-cover:rw-10-gusaba-gukwa-gathering:v2',
          'Saved reference differs',
        );
        require(
          (saved['errors'] as List).isEmpty,
          'Flutter errors: ${saved['errors']}',
        );
        await capture('$name-saved');
        cases.add({
          'name': name,
          'status': 'pass',
          'native_keyboard': true,
          'saved_reference': image(saved),
          'focused': focused,
        });
        stdout.writeln('$name PASS');
      }
    }
    await android(['shell', 'settings', 'put', 'system', 'font_scale', '1']);
    await android(['shell', 'settings', 'put', 'system', 'user_rotation', '0']);
    await Future<void>.delayed(const Duration(seconds: 2));
    await tap(find.text('Edit group photo'));
    await tap(find.byTooltip('Upload image'));
    final other = find.byValueKey('group-photo-rw-09-wedding-committee');
    await driver.runUnsynchronized(
      () => driver.scrollUntilVisible(
        find.byValueKey('group-photo-scroll'),
        other,
        dyScroll: -130,
      ),
    );
    await tapVisiblePhoto('rw-09-wedding-committee');
    await tap(find.byTooltip('Close photo collection'));
    require(
      image(await inspect()) == 'collect-cover:rw-10-gusaba-gukwa-gathering:v2',
      'Cancel changed saved photo',
    );
    cases.add({'name': 'cancel-draft', 'status': 'pass'});
    await tap(find.byTooltip('Remove image'));
    await driver.runUnsynchronized(
      () => driver.scrollIntoView(find.text('Save')),
    );
    await tap(find.text('Save'));
    await settle();
    final removed = await inspect();
    require(image(removed) == null, 'Removal did not clear saved image');
    require(
      (removed['errors'] as List).isEmpty,
      'Flutter errors: ${removed['errors']}',
    );
    await capture('photo-removed');
    cases.add({'name': 'remove-and-save', 'status': 'pass'});
  } catch (error) {
    failure = error.toString();
    await capture('failure');
    rethrow;
  } finally {
    await android([
      'shell',
      'settings',
      originalHandwriting == 'null' ? 'delete' : 'put',
      'secure',
      'stylus_handwriting_enabled',
      if (originalHandwriting != 'null') originalHandwriting,
    ]);
    for (final entry in original.entries) {
      await android([
        'shell',
        'settings',
        entry.value == 'null' ? 'delete' : 'put',
        'system',
        entry.key,
        if (entry.value != 'null') entry.value,
      ]);
    }
    final restored = <String, String>{};
    for (final key in original.keys) {
      restored[key] = await android([
        'shell',
        'settings',
        'get',
        'system',
        key,
      ]);
    }
    final restoredHandwriting = await android([
      'shell',
      'settings',
      'get',
      'secure',
      'stylus_handwriting_enabled',
    ]);
    File('${out.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'passed': cases.length,
        'expected': 6,
        'status': cases.length == 6 ? 'pass' : 'incomplete',
        'fixture_only': true,
        'input': 'Real Android IME; Flutter text emulation disabled',
        'avd': 'Collect_Design_Renderer_QA_20260905',
        'original_settings': original,
        'restored_settings': restored,
        'original_handwriting_setting': originalHandwriting,
        'restored_handwriting_setting': restoredHandwriting,
        'failure': failure,
        'cases': cases,
      }),
    );
    await driver.close();
  }
}
