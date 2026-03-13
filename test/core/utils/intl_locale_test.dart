import 'package:cool_app/core/utils/intl_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveIntlLocaleTag keeps supported locale tags', () {
    expect(resolveIntlLocaleTag(const Locale('fr')), 'fr');
    expect(resolveIntlLocaleTag(const Locale('en')), 'en');
  });

  test('resolveIntlLocaleTag falls back for unsupported locales', () {
    expect(resolveIntlLocaleTag(const Locale('rw')), 'en');
    expect(resolveIntlLocaleTag(const Locale('rw', 'RW')), 'en');
  });
}
