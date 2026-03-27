import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../../../core/config/country_catalog.dart';

const _coolNfcScheme = 'cool';
const _coolNfcMomoHost = 'momo';
const _coolDeepLinkHost = String.fromEnvironment(
  'COOL_DEEP_LINK_HOST',
  defaultValue: 'cool.app',
);
const _legacyCoolDeepLinkHosts = <String>{
  'cool.app',
  'www.cool.app',
  'cool.ikanisa.com',
  'www.cool.ikanisa.com',
};

/// NFC availability status.
enum NfcStatus { available, disabled, notSupported }

class NfcPaymentPayload {
  const NfcPaymentPayload({
    required this.recipientValue,
    required this.amount,
    this.recipientType = MomoRecipientType.phoneNumber,
    this.countryCode,
  });

  final String recipientValue;
  final String amount;
  final MomoRecipientType recipientType;
  final String? countryCode;

  String encode() {
    final country = (countryCode ?? '').trim().toUpperCase();
    return 'COOL:PAY:${recipientType.name}:$country:$recipientValue:$amount';
  }

  Uri toDeepLinkUri() {
    final country = (countryCode ?? '').trim().toUpperCase();
    return Uri.https(_coolDeepLinkHost, '/momo', <String, String>{
      'action': 'nfc_pay',
      'recipient': recipientValue,
      'amount': amount,
      'recipient_type': recipientType.name,
      if (country.isNotEmpty) 'country': country,
    });
  }

  /// Build a `tel:` URI containing the MoMo USSD code so that tapping the
  /// NFC tag launches the phone dialer instead of opening a browser.
  /// Returns `null` if the country is unknown and USSD can't be resolved.
  Uri? toUssdUri() {
    final cc = (countryCode ?? '').trim().toUpperCase();
    if (cc.isEmpty) return null;
    final country = CoolCountryCatalog.byIsoCode(cc);
    if (country == null) return null;
    final parsedAmount = int.tryParse(amount.replaceAll(RegExp(r'[^0-9]'), ''));
    if (parsedAmount == null || parsedAmount <= 0) return null;
    final ussd = country.buildUssdCode(
      recipientMomo: recipientValue,
      amount: parsedAmount,
      recipientType: recipientType,
    );
    // Android requires # encoded as %23 in tel: URIs.
    final encoded = ussd.replaceAll('#', '%23');
    return Uri.parse('tel:$encoded');
  }

  static NfcPaymentPayload? tryParse(String rawText) {
    final trimmed = rawText.trim();
    if (!trimmed.startsWith('COOL:')) {
      return null;
    }

    final parts = trimmed.split(':');
    if (parts.length >= 6 && parts[1] == 'PAY') {
      final recipientType = switch (parts[2]) {
        'code' => MomoRecipientType.code,
        _ => MomoRecipientType.phoneNumber,
      };
      final countryCode = parts[3].trim().isEmpty ? null : parts[3].trim();
      final recipientValue = parts[4].trim();
      final amount = parts.sublist(5).join(':').trim();
      if (recipientValue.isEmpty || amount.isEmpty) {
        return null;
      }
      return NfcPaymentPayload(
        recipientType: recipientType,
        countryCode: countryCode,
        recipientValue: recipientValue,
        amount: amount,
      );
    }

    // Legacy format: COOL:{phone}:{amount}
    if (parts.length >= 3) {
      final recipientValue = parts[1].trim();
      final amount = parts.sublist(2).join(':').trim();
      if (recipientValue.isEmpty || amount.isEmpty) {
        return null;
      }
      return NfcPaymentPayload(recipientValue: recipientValue, amount: amount);
    }

    return null;
  }

  static NfcPaymentPayload? tryParseUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final isCoolAppLink =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (() {
          final normalizedHost = uri.host.toLowerCase();
          final defaultHost = _coolDeepLinkHost.toLowerCase();
          return normalizedHost == defaultHost ||
              normalizedHost == 'www.$defaultHost' ||
              _legacyCoolDeepLinkHosts.contains(normalizedHost);
        })() &&
        segments.isNotEmpty &&
        segments.first.toLowerCase() == _coolNfcMomoHost;
    final isCustomScheme =
        uri.scheme == _coolNfcScheme &&
        ((uri.host.isNotEmpty && uri.host.toLowerCase() == _coolNfcMomoHost) ||
            (segments.isNotEmpty &&
                segments.first.toLowerCase() == _coolNfcMomoHost));

    if (!isCoolAppLink && !isCustomScheme) {
      return null;
    }

    final action = uri.queryParameters['action']?.trim().toLowerCase();
    if (action != 'nfc_pay') {
      return null;
    }

    final recipientValue = uri.queryParameters['recipient']?.trim() ?? '';
    final amount = uri.queryParameters['amount']?.trim() ?? '';
    if (recipientValue.isEmpty || amount.isEmpty) {
      return null;
    }

    final countryCode = uri.queryParameters['country']?.trim();
    final recipientType = switch (uri.queryParameters['recipient_type']) {
      'code' => MomoRecipientType.code,
      _ => MomoRecipientType.phoneNumber,
    };

    return NfcPaymentPayload(
      recipientValue: recipientValue,
      amount: amount,
      recipientType: recipientType,
      countryCode: countryCode?.isEmpty == true ? null : countryCode,
    );
  }
}

/// Result of an NFC read operation.
class NfcReadResult {
  const NfcReadResult({
    this.recipientValue,
    this.recipientType = MomoRecipientType.phoneNumber,
    this.amount,
    this.rawText,
    this.countryCode,
  });

  final String? recipientValue;
  final MomoRecipientType recipientType;
  final String? amount;
  final String? rawText;
  final String? countryCode;

  String? get phoneNumber =>
      recipientType == MomoRecipientType.phoneNumber ? recipientValue : null;
  String? get merchantCode =>
      recipientType == MomoRecipientType.code ? recipientValue : null;

  bool get hasPaymentData => recipientValue != null && amount != null;

  @override
  String toString() =>
      'NfcReadResult(recipientType: $recipientType, recipient: $recipientValue, amount: $amount, raw: $rawText)';
}

/// Service for NFC read/write operations.
///
/// - **Android**: Read AND Write
/// - **iOS**: Read ONLY (CoreNFC limitation)
///
/// Data format: NDEF Text record with `COOL:{phone}:{amount}` payload.
class NfcService {
  /// Whether the current platform supports NFC write.
  /// iOS CoreNFC only supports reading.
  static bool get canWrite => !kIsWeb && Platform.isAndroid;

  /// Check NFC availability on this device.
  static Future<NfcStatus> checkAvailability() async {
    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      return switch (availability) {
        NFCAvailability.available => NfcStatus.available,
        NFCAvailability.disabled => NfcStatus.disabled,
        NFCAvailability.not_supported => NfcStatus.notSupported,
      };
    } catch (_) {
      return NfcStatus.notSupported;
    }
  }

  /// Read an NFC tag and parse payment data.
  ///
  /// Returns [NfcReadResult] with parsed phone/amount if the tag
  /// contains a Cool payment record, otherwise returns raw text.
  static Future<NfcReadResult> readTag() async {
    try {
      // Start polling for an NFC tag (timeout after 30s).
      await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        iosAlertMessage: 'Tap NFC tag',
      );

      // Read NDEF records from the tag.
      final records = await FlutterNfcKit.readNDEFRecords();

      String? rawText;
      NfcPaymentPayload? parsedPayload;

      for (final record in records) {
        if (record is ndef.UriRecord) {
          rawText = record.uriString;

          if (rawText != null) {
            final uri = Uri.tryParse(rawText);
            if (uri != null) {
              parsedPayload = NfcPaymentPayload.tryParseUri(uri);
            }
          }
          if (parsedPayload != null) {
            break;
          }
        } else if (record is ndef.TextRecord) {
          rawText = record.text;

          if (rawText != null) {
            parsedPayload = NfcPaymentPayload.tryParse(rawText);
          }
          if (parsedPayload != null) {
            break;
          }
        }
      }

      await FlutterNfcKit.finish(iosAlertMessage: 'Tag read successfully');

      return NfcReadResult(
        recipientValue: parsedPayload?.recipientValue,
        recipientType:
            parsedPayload?.recipientType ?? MomoRecipientType.phoneNumber,
        amount: parsedPayload?.amount,
        rawText: rawText,
        countryCode: parsedPayload?.countryCode,
      );
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Read failed');
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> cancelSession({String? reason}) async {
    try {
      await FlutterNfcKit.finish(
        iosErrorMessage: reason ?? 'Cancelled',
      ).timeout(const Duration(milliseconds: 400));
    } catch (_) {
      // Best effort only. The NFC session may already be closed.
    }
  }

  /// Write payment data to an NFC tag (Android only).
  ///
  /// Writes an NDEF text record with format `COOL:{phone}:{amount}`.
  static Future<void> writeTag({
    required String recipientValue,
    required String amount,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
    String? countryCode,
  }) async {
    if (!canWrite) {
      throw UnsupportedError('NFC write is only supported on Android');
    }

    try {
      // Poll for a writable tag.
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
      );

      if (tag.ndefWritable != true) {
        await FlutterNfcKit.finish();
        throw Exception('This NFC tag is not writable');
      }

      // Build NDEF text record with Cool payment format.
      final payload = NfcPaymentPayload(
        recipientValue: recipientValue,
        amount: amount,
        recipientType: recipientType,
        countryCode: countryCode,
      );
      final textRecord = ndef.TextRecord(
        text: payload.encode(),
        language: 'en',
      );
      // Prefer tel: USSD URI so tapping the NFC tag launches the dialer
      // instead of Chrome. Fall back to deep link for unknown countries.
      final tagUri = payload.toUssdUri() ?? payload.toDeepLinkUri();
      final uriRecord = ndef.UriRecord.fromUri(tagUri);

      await FlutterNfcKit.writeNDEFRecords([uriRecord, textRecord]);
      await FlutterNfcKit.finish();
    } catch (e) {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}
      rethrow;
    }
  }
}
