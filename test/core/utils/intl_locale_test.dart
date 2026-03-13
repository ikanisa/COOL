import 'package:cool_app/core/utils/intl_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveIntlLocaleTag always resolves to English', () {
    expect(resolveIntlLocaleTag(const Locale('sw')), 'en');
    expect(resolveIntlLocaleTag(const Locale('en')), 'en');
  });

  test('resolveIntlLocaleTag falls back for unsupported locales', () {
    expect(resolveIntlLocaleTag(const Locale('rw')), 'en');
    expect(resolveIntlLocaleTag(const Locale('rw', 'RW')), 'en');
  });
}
