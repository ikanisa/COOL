import 'country_catalog.dart';

/// Central product invariants for the Rwanda-only app.
abstract final class AppMarket {
  static const countryCode = 'RW';
  static const languageCode = 'en';

  static CoolCountry get country =>
      CoolCountryCatalog.resolve(country: countryCode);
}
