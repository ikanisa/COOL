import 'package:cool_app/core/utils/intl_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolveIntlLocaleTag always resolves to English', (
    tester,
  ) async {
    expect(resolveIntlLocaleTag(const Locale('sw')), 'en');
    expect(resolveIntlLocaleTag(const Locale('en')), 'en');
  });

  testWidgets('resolveIntlLocale ignores the device locale', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'fr',
      'FR',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    String? resolvedLocale;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            resolvedLocale = resolveIntlLocale(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolvedLocale, 'en');
    expect(resolveIntlLocaleTag(const Locale('rw', 'RW')), 'en');
  });
}
