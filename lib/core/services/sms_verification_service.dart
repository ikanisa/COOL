import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'momo_sms_parser.dart';

/// Result of SMS payment verification.
class SmsVerificationResult {
  const SmsVerificationResult({
    required this.confirmed,
    this.amount,
    this.reference,
    this.senderMessage,
  });

  final bool confirmed;
  final int? amount;
  final String? reference;
  final String? senderMessage;
}

/// Listens for incoming M-Money confirmation SMS after USSD payment.
///
/// - **Android**: Listens for SMS from approved M-Money sender IDs
/// - **iOS**: No SMS access — uses manual confirmation fallback
///
class SmsVerificationService {
  SmsVerificationService._();

  static final SmsVerificationService instance = SmsVerificationService._();

  /// Amount pattern: matches digits with optional commas
  static final _amountPattern = RegExp(r'(\d[\d,]*)\s*RWF');

  /// Reference pattern: matches Ref/TxnID codes
  static final _refPattern = RegExp(
    r'(?:Ref|TxnID|ID)[:\s]*([A-Z0-9]+)',
    caseSensitive: false,
  );

  /// Whether SMS listening is supported on this platform.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Listen for a MoMo confirmation SMS.
  ///
  /// Returns a [SmsVerificationResult] when a matching SMS is received,
  /// or after [timeout] elapses.
  ///
  /// On iOS / web this immediately returns unconfirmed (caller should
  /// show the manual confirmation fallback).
  Future<SmsVerificationResult> waitForConfirmation({
    required int expectedAmount,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!isSupported) {
      // iOS / web — caller should show manual confirmation UI
      return const SmsVerificationResult(confirmed: false);
    }

    // On Android, we poll for SMS confirmation.
    // In a production app, this would use a platform channel or
    // an SMS listener plugin. For this MVP, we simulate the wait
    // and provide the manual fallback.
    //
    // The actual SMS reading could use the `sms_receiver` or
    // `telephony` package. For now, we provide the structure
    // and return unconfirmed so the manual fallback is used.
    //
    // TODO(production): Integrate real SMS listener via platform channel
    return const SmsVerificationResult(confirmed: false);
  }

  /// Parse a MoMo SMS message body to extract payment details.
  ///
  /// Returns null if the message doesn't match known MoMo patterns.
  static SmsVerificationResult? parseMessage(String message) {
    // Check if message contains amount
    final amountMatch = _amountPattern.firstMatch(message);
    if (amountMatch == null) return null;

    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = int.tryParse(amountStr);

    // Extract reference if present
    final refMatch = _refPattern.firstMatch(message);
    final reference = refMatch?.group(1);

    // Check for success indicators
    final isSuccess =
        message.contains('sent') ||
        message.contains('Successful') ||
        message.contains('completed') ||
        message.contains('confirmed');

    if (!isSuccess) return null;

    return SmsVerificationResult(
      confirmed: true,
      amount: amount,
      reference: reference,
      senderMessage: message,
    );
  }

  /// Check if a sender ID is an approved M-Money sender.
  static bool isMomoSender(String senderId) {
    return MomoSmsParser.isApprovedSender(senderId);
  }
}
