import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/services/hive_runtime.dart';

/// A purchased ticket stored locally.
class PurchasedTicket {
  PurchasedTicket({
    required this.id,
    required this.matchId,
    required this.matchTitle,
    required this.venue,
    required this.date,
    required this.kickoff,
    required this.seatCategory,
    required this.qty,
    required this.unitPrice,
    required this.totalPrice,
    required this.momoReference,
    required this.purchasedAt,
    this.status = TicketStatus.pending,
  });

  factory PurchasedTicket.fromJson(Map<String, dynamic> json) {
    return PurchasedTicket(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      matchTitle: json['matchTitle'] as String,
      venue: json['venue'] as String,
      date: json['date'] as String,
      kickoff: json['kickoff'] as String,
      seatCategory: json['seatCategory'] as String,
      qty: json['qty'] as int,
      unitPrice: json['unitPrice'] as int,
      totalPrice: json['totalPrice'] as int,
      momoReference: json['momoReference'] as String,
      purchasedAt: DateTime.parse(json['purchasedAt'] as String),
      status: TicketStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => TicketStatus.pending,
      ),
    );
  }

  final String id;
  final String matchId;
  final String matchTitle;
  final String venue;
  final String date;
  final String kickoff;
  final String seatCategory;
  final int qty;
  final int unitPrice;
  final int totalPrice;
  final String momoReference;
  final DateTime purchasedAt;
  TicketStatus status;

  /// Generates the HMAC-signed QR data.
  String get qrData => TicketService.generateQrData(this);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'matchId': matchId,
    'matchTitle': matchTitle,
    'venue': venue,
    'date': date,
    'kickoff': kickoff,
    'seatCategory': seatCategory,
    'qty': qty,
    'unitPrice': unitPrice,
    'totalPrice': totalPrice,
    'momoReference': momoReference,
    'purchasedAt': purchasedAt.toIso8601String(),
    'status': status.name,
  };
}

enum TicketStatus { pending, valid, used, cancelled }

/// Result of verifying a ticket QR code.
class TicketVerifyResult {
  const TicketVerifyResult({
    required this.isValid,
    this.ticket,
    this.errorMessage,
  });

  final bool isValid;
  final PurchasedTicket? ticket;
  final String? errorMessage;
}

/// Manages ticket purchase, storage, retrieval, and QR verification.
///
/// QR data format: `COOL-TKT:{ticketId}:{matchId}:{timestamp}:{hmac}`
class TicketService {
  TicketService({required OpenHiveBox<String> openBox}) : _openBox = openBox;

  final OpenHiveBox<String> _openBox;

  static const _boxName = 'purchased_tickets';

  /// Signing key for offline QR verification — injected via --dart-define.
  static const _hmacSecret = String.fromEnvironment('TICKET_QR_HMAC_SECRET');

  Future<PurchasedTicket> purchaseTicket({
    required String matchId,
    required String matchTitle,
    required String venue,
    required String date,
    required String kickoff,
    required String seatCategory,
    required int qty,
    required int unitPrice,
    required String momoReference,
  }) async {
    final now = DateTime.now();
    final ticketId =
        'TKT-${now.millisecondsSinceEpoch}-${matchId.hashCode.abs() % 10000}';

    final ticket = PurchasedTicket(
      id: ticketId,
      matchId: matchId,
      matchTitle: matchTitle,
      venue: venue,
      date: date,
      kickoff: kickoff,
      seatCategory: seatCategory,
      qty: qty,
      unitPrice: unitPrice,
      totalPrice: unitPrice * qty,
      momoReference: momoReference,
      purchasedAt: now,
    );

    final box = await _openBox(_boxName);
    await box.put(ticket.id, jsonEncode(ticket.toJson()));

    return ticket;
  }

  Future<List<PurchasedTicket>> getMyTickets() async {
    final box = await _openBox(_boxName);
    final tickets = <PurchasedTicket>[];

    for (final key in box.keys) {
      try {
        final json = jsonDecode(box.get(key)!) as Map<String, dynamic>;
        tickets.add(PurchasedTicket.fromJson(json));
      } catch (_) {
        // Skip corrupted entries.
      }
    }

    tickets.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    return tickets;
  }

  Future<void> markUsed(String ticketId) async {
    final box = await _openBox(_boxName);
    final raw = box.get(ticketId);
    if (raw == null) {
      return;
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    json['status'] = TicketStatus.used.name;
    await box.put(ticketId, jsonEncode(json));
  }

  static String generateQrData(PurchasedTicket ticket) {
    final payload =
        '${ticket.id}:${ticket.matchId}:${ticket.purchasedAt.millisecondsSinceEpoch}';
    final hmac = _computeHmac(payload);
    return 'COOL-TKT:$payload:$hmac';
  }

  Future<TicketVerifyResult> verifyQr(String qrData) async {
    if (!qrData.startsWith('COOL-TKT:')) {
      return const TicketVerifyResult(
        isValid: false,
        errorMessage: 'Not a Cool ticket QR code',
      );
    }

    final parts = qrData.substring('COOL-TKT:'.length).split(':');
    if (parts.length < 4) {
      return const TicketVerifyResult(
        isValid: false,
        errorMessage: 'Invalid ticket QR format',
      );
    }

    final ticketId = parts[0];
    final matchId = parts[1];
    final timestamp = parts[2];
    final receivedHmac = parts[3];

    final payload = '$ticketId:$matchId:$timestamp';
    final expectedHmac = _computeHmac(payload);

    if (receivedHmac != expectedHmac) {
      return const TicketVerifyResult(
        isValid: false,
        errorMessage: 'Invalid ticket — signature mismatch',
      );
    }

    final box = await _openBox(_boxName);
    final raw = box.get(ticketId);

    if (raw != null) {
      final ticket = PurchasedTicket.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      if (ticket.status == TicketStatus.used) {
        return TicketVerifyResult(
          isValid: false,
          ticket: ticket,
          errorMessage: 'Ticket already used',
        );
      }

      return TicketVerifyResult(isValid: true, ticket: ticket);
    }

    return const TicketVerifyResult(
      isValid: true,
      errorMessage: 'Valid signature — ticket not found on this device',
    );
  }

  static String _computeHmac(String payload) {
    final secret = _hmacSecret.trim();
    if (secret.isEmpty) {
      throw StateError('TICKET_QR_HMAC_SECRET is not configured.');
    }

    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final digest = Hmac(sha256, key).convert(bytes);
    return digest.toString().substring(0, 12);
  }
}
