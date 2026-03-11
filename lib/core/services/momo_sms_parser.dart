/// Heuristic on-device MoMo SMS parser used before server-side AI parsing.
///
/// This parser is intentionally lightweight and deterministic. It is used for:
/// - strict sender allowlisting on the device
/// - coarse extraction of visible fields from known SMS formats
/// - populating `detected_*` hints when raw SMS messages are uploaded
///
/// The full AI-backed normalization pipeline lives in the Supabase Edge
/// Function `parse-momo-sms`, where OpenAI/Gemini keys can stay server-side.
/// The mobile app must not call those vendors directly or ship model API keys.
///
/// Each supported provider/country has its own [MomoSmsPattern]. The parser
/// iterates through all registered patterns and returns the first match.
///
/// **Extensibility**: To add a new country or provider, create a new
/// [MomoSmsPattern] and register it in [MomoSmsParser.patterns].
class MomoSmsParser {
  const MomoSmsParser._();

  /// Approved sender IDs for automatic financial-transaction verification.
  ///
  /// Keep this list exact and narrow. We only process confirmed Rwanda MTN
  /// M-Money sender aliases instead of broad carrier keywords.
  static const List<String> approvedSenderIds = ['M-Money', 'MobileMoney'];

  // ── Registered patterns (add new countries here) ───────────────────────

  static const List<MomoSmsPattern> patterns = [
    // MTN MoMo Rwanda
    MomoSmsPattern(
      country: 'RW',
      provider: 'MTN',
      senderIds: approvedSenderIds,
      templates: [
        // Received money: "You have received 5,000 RWF from 0788123456. Your new balance is 12,000 RWF. TxId: 123456789."
        MomoSmsTemplate(
          type: MomoTxType.received,
          pattern: r'(?:received|recu)\s+([\d,\.]+)\s*(?:RWF|Frw)',
          txIdPattern: r'(?:TxId|Ref|ID)[:\s]*(\w+)',
        ),
        // Sent money: "You have sent 3,000 RWF to 0788654321. Fee: 50 RWF. TxId: 987654321."
        MomoSmsTemplate(
          type: MomoTxType.sent,
          pattern: r'(?:sent|envoye)\s+([\d,\.]+)\s*(?:RWF|Frw)',
          txIdPattern: r'(?:TxId|Ref|ID)[:\s]*(\w+)',
        ),
        // Payment: "Payment of 10,000 RWF to MERCHANT_NAME confirmed. TxId: 111222333."
        MomoSmsTemplate(
          type: MomoTxType.payment,
          pattern: r'(?:Payment|Paiement)\s+(?:of\s+)?([\d,\.]+)\s*(?:RWF|Frw)',
          txIdPattern: r'(?:TxId|Ref|ID)[:\s]*(\w+)',
        ),
      ],
    ),

    // ── Add more countries below ─────────────────────────────────────────
    //
    // Example: MTN MoMo DRC (Congolese Franc)
    // MomoSmsPattern(
    //   country: 'CD',
    //   provider: 'MTN',
    //   senderKeywords: ['MobileMoney', 'MTN'],
    //   templates: [
    //     MomoSmsTemplate(
    //       type: MomoTxType.received,
    //       pattern: r'(?:received|recu)\s+([\d,\.]+)\s*(?:CDF|FC)',
    //       txIdPattern: r'(?:TxId|Ref|ID)[:\s]*(\w+)',
    //     ),
    //   ],
    // ),
    //
    // Example: M-Pesa Kenya
    // MomoSmsPattern(
    //   country: 'KE',
    //   provider: 'M-Pesa',
    //   senderKeywords: ['MPESA', 'M-PESA', 'Safaricom'],
    //   templates: [
    //     MomoSmsTemplate(
    //       type: MomoTxType.received,
    //       pattern: r'(?:received|confirmed).*?Ksh([\d,\.]+)',
    //       txIdPattern: r'^([A-Z0-9]{10})',
    //     ),
    //   ],
    // ),
  ];

  /// Attempts to parse [smsBody] from [sender] into a [MomoTransaction].
  ///
  /// Returns `null` if no registered pattern matches.
  static MomoTransaction? parse({
    required String sender,
    required String smsBody,
  }) {
    for (final pattern in patterns) {
      if (!pattern.matchesSender(sender)) continue;

      final tx = pattern.tryParse(smsBody, sender: sender);
      if (tx != null) return tx;
    }
    return null;
  }

  static bool isApprovedSender(String sender) {
    return patterns.any((pattern) => pattern.matchesSender(sender));
  }

  static String normalizeSenderId(String sender) {
    return sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pattern / template models
// ═══════════════════════════════════════════════════════════════════════════

class MomoSmsPattern {
  const MomoSmsPattern({
    required this.country,
    required this.provider,
    required this.senderIds,
    required this.templates,
  });

  final String country;
  final String provider;

  /// Approved sender IDs to match against the SMS sender field.
  final List<String> senderIds;
  final List<MomoSmsTemplate> templates;

  bool matchesSender(String sender) {
    final normalizedSender = MomoSmsParser.normalizeSenderId(sender);
    return senderIds.any(
      (senderId) =>
          MomoSmsParser.normalizeSenderId(senderId) == normalizedSender,
    );
  }

  MomoTransaction? tryParse(String body, {required String sender}) {
    for (final tpl in templates) {
      final match = RegExp(tpl.pattern, caseSensitive: false).firstMatch(body);
      if (match == null) continue;

      final rawAmount = match.group(1) ?? '0';
      final amount = _parseAmount(rawAmount);

      String? txId;
      if (tpl.txIdPattern != null) {
        final txMatch = RegExp(
          tpl.txIdPattern!,
          caseSensitive: false,
        ).firstMatch(body);
        txId = txMatch?.group(1);
      }

      return MomoTransaction(
        type: tpl.type,
        amountRwf: amount,
        transactionId: txId,
        country: country,
        provider: provider,
        sender: sender,
        rawMessage: body,
        receivedAt: DateTime.now(),
      );
    }
    return null;
  }

  static int _parseAmount(String raw) {
    // Remove commas, dots used as thousands separator, then parse.
    final cleaned = raw.replaceAll(',', '').replaceAll(' ', '');
    return double.tryParse(cleaned)?.round() ?? 0;
  }
}

class MomoSmsTemplate {
  const MomoSmsTemplate({
    required this.type,
    required this.pattern,
    this.txIdPattern,
  });

  final MomoTxType type;

  /// Regex with one capture group for the amount.
  final String pattern;

  /// Optional regex with one capture group for the transaction ID.
  final String? txIdPattern;
}

// ═══════════════════════════════════════════════════════════════════════════
// Transaction model
// ═══════════════════════════════════════════════════════════════════════════

enum MomoTxType { received, sent, payment }

class MomoTransaction {
  const MomoTransaction({
    required this.type,
    required this.amountRwf,
    required this.country,
    required this.provider,
    required this.sender,
    required this.rawMessage,
    required this.receivedAt,
    this.transactionId,
  });

  final MomoTxType type;
  final int amountRwf;
  final String? transactionId;
  final String country;
  final String provider;
  final String sender;
  final String rawMessage;
  final DateTime receivedAt;

  @override
  String toString() =>
      'MomoTransaction($type, $amountRwf RWF, txId=$transactionId, $provider/$country)';
}
