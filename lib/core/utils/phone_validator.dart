/// Phone number validation utilities.
///
/// Key distinction:
/// - WhatsApp number: used for OTP, broadly international.
/// - MoMo number: a country-specific mobile MSISDN.
/// - MoMo code: a separate merchant or payment code where supported.
library;

import '../config/country_catalog.dart';

/// Rwanda mobile prefixes (after +250, the "7X" digit pair).
///
/// MTN Rwanda  : 78, 79
/// Airtel Rwanda: 72, 73
/// Other valid : 75 (legacy)
abstract final class RwandaPrefixes {
  static const mtn = {'78', '79'};
  static const airtel = {'72', '73'};
  static const allValid = {'72', '73', '75', '78', '79'};
}

/// Detected Rwandan operator.
enum RwandaProvider { mtn, airtel, unknown }

/// Central phone-number and MoMo validation utility.
abstract final class PhoneValidator {
  // ──────────────────────────────────────────────────────────────────────
  // Rwanda-specific
  // ──────────────────────────────────────────────────────────────────────

  /// Strips a Rwandan phone to its 9-digit local form (e.g. `78XXXXXXX`).
  /// Returns `null` if the input is too short/malformed.
  static String? toRwandanLocal(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // Strip country code 250
    if (digits.startsWith('250') && digits.length > 9) {
      digits = digits.substring(3);
    }

    // Strip leading zero (0781234567 → 781234567)
    if (digits.startsWith('0') && digits.length == 10) {
      digits = digits.substring(1);
    }

    return digits.length == 9 ? digits : null;
  }

  /// Whether [phone] is a valid Rwandan mobile number (any operator).
  static bool isValidRwandanMobile(String phone) {
    final local = toRwandanLocal(phone);
    if (local == null) return false;
    final prefix = local.substring(0, 2);
    return RwandaPrefixes.allValid.contains(prefix);
  }

  /// Whether [phone] is an MTN Rwanda number (78X or 79X).
  static bool isValidMtnRwanda(String phone) {
    final local = toRwandanLocal(phone);
    if (local == null) return false;
    return RwandaPrefixes.mtn.contains(local.substring(0, 2));
  }

  /// Whether [phone] is an Airtel Rwanda number (72X or 73X).
  static bool isValidAirtelRwanda(String phone) {
    final local = toRwandanLocal(phone);
    if (local == null) return false;
    return RwandaPrefixes.airtel.contains(local.substring(0, 2));
  }

  /// Detect operator from phone. Returns [RwandaProvider.unknown] when
  /// the number is valid but the prefix is unrecognised (e.g. 75X).
  static RwandaProvider? detectRwandanProvider(String phone) {
    final local = toRwandanLocal(phone);
    if (local == null) return null;
    final prefix = local.substring(0, 2);
    if (RwandaPrefixes.mtn.contains(prefix)) return RwandaProvider.mtn;
    if (RwandaPrefixes.airtel.contains(prefix)) return RwandaProvider.airtel;
    if (RwandaPrefixes.allValid.contains(prefix)) {
      return RwandaProvider.unknown;
    }
    return null;
  }

  /// Friendly display: `+250 78X XXX XXX`
  static String formatRwandanDisplay(String phone) {
    final local = toRwandanLocal(phone);
    if (local == null || local.length != 9) return phone;
    return '+250 ${local.substring(0, 3)} ${local.substring(3, 6)} ${local.substring(6)}';
  }

  // ──────────────────────────────────────────────────────────────────────
  // Country-aware MoMo validation
  // ──────────────────────────────────────────────────────────────────────

  /// Validate a MoMo number against the user's country.
  /// Returns `null` if valid, or an error message string.
  static String? validateMomoNumber(String phone, String countryCode) {
    return validateMomoNumberForCountry(
      phone,
      CoolCountryCatalog.resolve(country: countryCode),
    );
  }

  /// Validate a MoMo number against a fully resolved [country].
  /// Returns `null` if valid, or an error message string.
  static String? validateMomoNumberForCountry(
    String phone,
    CoolCountry country,
  ) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return 'MoMo number is required';

    try {
      country.buildE164Phone(trimmed);
      return null;
    } on FormatException catch (error) {
      final message = error.message.toString().trim();
      return message.isEmpty
          ? 'Enter a valid ${country.name} mobile money number'
          : message;
    } on UnsupportedError catch (error) {
      final message = error.message.toString().trim();
      return message.isEmpty
          ? 'Mobile money is not configured for ${country.name}'
          : message;
    }
  }

  /// Validate a MoMo merchant code (e.g. MTN MoMo pay code).
  /// Returns `null` if valid, or an error message.
  static String? validateMomoCode(
    String code, {
    CoolCountry? country,
    bool required = false,
  }) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return required ? 'MoMo code is required' : null;
    }

    if (country == null) {
      final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 4 || digits.length > 8) {
        return 'MoMo code must be 4-8 digits';
      }
      if (digits != trimmed) {
        return 'MoMo code must contain only numbers';
      }
      return null;
    }

    try {
      country.normalizeMerchantCode(trimmed);
      return null;
    } on FormatException catch (error) {
      final message = error.message.toString().trim();
      return message.isEmpty ? 'Enter a valid MoMo code' : message;
    } on UnsupportedError catch (error) {
      final message = error.message.toString().trim();
      return message.isEmpty
          ? 'Merchant-code payments are not configured for ${country.name}'
          : message;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Auto-populate logic
  // ──────────────────────────────────────────────────────────────────────

  /// Whether the WhatsApp OTP number should auto-populate the MoMo field.
  /// True only when the number is an MTN Rwanda number (since MTN is the
  /// dominant MoMo provider in Rwanda).
  static bool shouldAutoPopulateMomo(String whatsappPhone, String countryCode) {
    if (countryCode.toUpperCase() != 'RW') return false;
    return isValidMtnRwanda(whatsappPhone);
  }

  /// Returns the provider display label for a given phone + country.
  static String? providerLabel(String phone, String countryCode) {
    if (countryCode.toUpperCase() != 'RW') return null;
    final provider = detectRwandanProvider(phone);
    return switch (provider) {
      RwandaProvider.mtn => 'MTN Rwanda',
      RwandaProvider.airtel => 'Airtel Rwanda',
      RwandaProvider.unknown => 'Rwanda Mobile',
      null => null,
    };
  }

  // ──────────────────────────────────────────────────────────────────────
  // OTP input validation (WhatsApp number — any country)
  // ──────────────────────────────────────────────────────────────────────

  /// Basic validation for the OTP phone entry. WhatsApp numbers can be
  /// from any country, but must have enough digits to be plausible.
  /// Returns `null` if valid, or an error message.
  static String? validateOtpPhone(String phone, CoolCountry country) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return 'Enter your phone number';

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    // Rwanda-specific: must be a valid mobile prefix
    if (country.isoCode == 'RW') {
      final local = toRwandanLocal(trimmed);
      if (local == null) return 'Enter a 9-digit Rwandan number';
      if (!local.startsWith('7')) {
        return 'Rwandan mobile numbers start with 07';
      }
      return null;
    }

    // Generic: at least 7 digits (shortest international numbers)
    if (digits.length < 7) return 'Enter a valid phone number';
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────
  // USSD QR data
  // ──────────────────────────────────────────────────────────────────────

  /// Generate USSD-compatible QR data for a MoMo number.
  /// Uses the local format prefixed with the dial code.
  static String generateMomoQrData(String momoNumber, CoolCountry country) {
    final e164 = country.buildE164Phone(momoNumber);
    return 'momo://${e164.replaceAll(RegExp(r'[^0-9+]'), '')}';
  }
}
