import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web bootstrap registers the custom service worker', () {
    final bootstrap = File(
      '${Directory.current.path}/web/flutter_bootstrap.js',
    ).readAsStringSync();

    expect(bootstrap, contains('serviceWorkerUrl'));
    expect(bootstrap, contains('custom-sw.js'));
    expect(
      bootstrap,
      contains('window._coolServiceWorkerVersion = {{flutter_service_worker_version}};'),
    );
    expect(
      bootstrap,
      contains('serviceWorkerVersion: window._coolServiceWorkerVersion'),
    );
  });

  test('index loads the PWA bridge before Flutter bootstrap', () {
    final index = File('${Directory.current.path}/web/index.html')
        .readAsStringSync();

    final bridgeIndex = index.indexOf('pwa-bridge.js');
    final bootstrapIndex = index.indexOf('flutter_bootstrap.js');

    expect(bridgeIndex, isNonNegative);
    expect(bootstrapIndex, isNonNegative);
    expect(bridgeIndex, lessThan(bootstrapIndex));
  });

  test('manifest exposes admin shortcut and maskable icons', () {
    final manifest = jsonDecode(
      File('${Directory.current.path}/web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final shortcuts = (manifest['shortcuts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      shortcuts.any((shortcut) => shortcut['url'] == '/admin'),
      isTrue,
    );

    final icons = (manifest['icons'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      icons.any((icon) => icon['purpose'] == 'maskable'),
      isTrue,
    );
  });

  test('web hosting config includes SPA rewrites', () {
    final config = jsonDecode(
      File('${Directory.current.path}/firebase.webapp.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final hosting = config['hosting'] as Map<String, dynamic>;
    final rewrites = (hosting['rewrites'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      rewrites.any(
        (rewrite) =>
            rewrite['source'] == '**' &&
            rewrite['destination'] == '/index.html',
      ),
      isTrue,
    );
  });
}
