import 'package:collect_app/l10n/collect_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Collect supports English as its only product language', () {
    expect(
      CollectLocalizations.supportedLocales.map(
        (locale) => locale.languageCode,
      ),
      orderedEquals(['en']),
    );
  });

  test('critical contribution copy remains centralized in English', () {
    const localizations = CollectLocalizations(Locale('en'));
    expect(localizations.text('momoContribution'), 'MoMo contribution');
    expect(localizations.text('continueToMomo'), 'Continue to MoMo');
    expect(localizations.text('bankTransfer'), 'Bank transfer');
    expect(localizations.text('noActivePaymentRoute'), isNotEmpty);
  });

  test('unknown languages fail safely to English', () {
    expect(
      const CollectLocalizations(Locale('de')).text('momoContribution'),
      'MoMo contribution',
    );
  });
}
