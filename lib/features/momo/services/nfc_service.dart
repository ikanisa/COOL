import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

/// NFC availability status.
enum NfcStatus {
  available,
  disabled,
  notSupported,
}

/// Result of an NFC read operation.
class NfcReadResult {
  const NfcReadResult({this.phoneNumber, this.amount, this.rawText});

  final String? phoneNumber;
  final String? amount;
  final String? rawText;

  bool get hasPaymentData => phoneNumber != null && amount != null;

  @override
  String toString() =>
      'NfcReadResult(phone: $phoneNumber, amount: $amount, raw: $rawText)';
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
        iosAlertMessage: 'Hold your phone near the NFC tag',
      );

      // Read NDEF records from the tag.
      final records = await FlutterNfcKit.readNDEFRecords();

      String? rawText;
      String? phoneNumber;
      String? amount;

      for (final record in records) {
        if (record is ndef.TextRecord) {
          rawText = record.text;

          // Parse Cool payment format: COOL:{phone}:{amount}
          if (rawText != null && rawText.startsWith('COOL:')) {
            final parts = rawText.split(':');
            if (parts.length >= 3) {
              phoneNumber = parts[1];
              amount = parts[2];
            }
          }
          break;
        }
      }

      await FlutterNfcKit.finish(iosAlertMessage: 'Tag read successfully');

      return NfcReadResult(
        phoneNumber: phoneNumber,
        amount: amount,
        rawText: rawText,
      );
    } catch (e) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Read failed');
      } catch (_) {}
      rethrow;
    }
  }

  /// Write payment data to an NFC tag (Android only).
  ///
  /// Writes an NDEF text record with format `COOL:{phone}:{amount}`.
  static Future<void> writeTag({
    required String phoneNumber,
    required String amount,
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
      final payload = 'COOL:$phoneNumber:$amount';
      final record = ndef.TextRecord(
        text: payload,
        language: 'en',
      );

      await FlutterNfcKit.writeNDEFRecords([record]);
      await FlutterNfcKit.finish();
    } catch (e) {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}
      rethrow;
    }
  }
}
