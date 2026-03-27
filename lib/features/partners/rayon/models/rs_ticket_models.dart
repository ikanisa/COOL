part of 'rs_models.dart';

class RsMatch extends Equatable {
  const RsMatch({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.venue,
    required this.matchDate,
    required this.kickoffTime,
    required this.isOnSale,
    required this.ticketGeneralPrice,
    required this.ticketVipPrice,
    required this.saleStartsAt,
    required this.capacity,
    this.soldCount = 0,
    this.imageUrl,
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final String venue;
  final DateTime matchDate;
  final String kickoffTime;
  final bool isOnSale;
  final int ticketGeneralPrice;
  final int ticketVipPrice;
  final DateTime saleStartsAt;
  final int capacity;
  final int soldCount;
  final String? imageUrl;

  bool get isSoldOut => capacity > 0 && soldCount >= capacity;

  int get remainingCapacity =>
      capacity > 0 ? (capacity - soldCount).clamp(0, capacity) : 0;

  bool isAccessibleForTier(FanTier tier) {
    if (!isOnSale || capacity <= 0 || isSoldOut) {
      return false;
    }

    final accessStart = switch (tier) {
      FanTier.platinum => saleStartsAt.subtract(const Duration(hours: 72)),
      FanTier.gold => saleStartsAt.subtract(const Duration(hours: 48)),
      FanTier.silver => saleStartsAt.subtract(const Duration(hours: 24)),
      FanTier.blue => saleStartsAt,
    };

    final now = DateTime.now();
    return !now.isBefore(accessStart);
  }

  factory RsMatch.fromJson(RsJsonMap json) {
    final matchDate =
        _asDateTime(json['match_date'] ?? json['matchDate']) ?? DateTime.now();

    return RsMatch(
      id: _asString(json['id']),
      homeTeam: _asString(
        json['home_team'] ?? json['homeTeam'],
        fallback: 'Rayon Sports FC',
      ),
      awayTeam: _asString(
        json['away_team'] ?? json['awayTeam'],
        fallback: 'Opponent',
      ),
      competition: _asString(
        json['competition'],
        fallback: 'Rwanda Premier League',
      ),
      venue: _asString(json['venue'], fallback: 'Kigali Pelé Stadium'),
      matchDate: matchDate,
      kickoffTime: _normalizeKickoff(
        json['kickoff_time'] ?? json['kickoffTime'],
      ),
      isOnSale: _asBool(json['is_on_sale'] ?? json['isOnSale'], fallback: true),
      ticketGeneralPrice: _asInt(
        json['ticket_general_price'] ?? json['ticketGeneralPrice'],
      ),
      ticketVipPrice: _asInt(
        json['ticket_vip_price'] ?? json['ticketVipPrice'],
      ),
      saleStartsAt:
          _asDateTime(json['sale_starts_at'] ?? json['saleStartsAt']) ??
          matchDate.subtract(const Duration(days: 7)),
      capacity: _asInt(json['capacity'], fallback: 0),
      soldCount: _asInt(json['sold_count'] ?? json['soldCount'], fallback: 0),
      imageUrl: _asNullableString(json['image_url'] ?? json['imageUrl']),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'home_team': homeTeam,
      'away_team': awayTeam,
      'competition': competition,
      'venue': venue,
      'match_date': matchDate.toIso8601String(),
      'kickoff_time': kickoffTime,
      'is_on_sale': isOnSale,
      'ticket_general_price': ticketGeneralPrice,
      'ticket_vip_price': ticketVipPrice,
      'sale_starts_at': saleStartsAt.toIso8601String(),
      'capacity': capacity,
      'sold_count': soldCount,
      'image_url': imageUrl,
    };
  }

  RsMatch copyWith({
    String? id,
    String? homeTeam,
    String? awayTeam,
    String? competition,
    String? venue,
    DateTime? matchDate,
    String? kickoffTime,
    bool? isOnSale,
    int? ticketGeneralPrice,
    int? ticketVipPrice,
    DateTime? saleStartsAt,
    int? capacity,
    int? soldCount,
    Object? imageUrl = _unset,
  }) {
    return RsMatch(
      id: id ?? this.id,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      competition: competition ?? this.competition,
      venue: venue ?? this.venue,
      matchDate: matchDate ?? this.matchDate,
      kickoffTime: kickoffTime ?? this.kickoffTime,
      isOnSale: isOnSale ?? this.isOnSale,
      ticketGeneralPrice: ticketGeneralPrice ?? this.ticketGeneralPrice,
      ticketVipPrice: ticketVipPrice ?? this.ticketVipPrice,
      saleStartsAt: saleStartsAt ?? this.saleStartsAt,
      capacity: capacity ?? this.capacity,
      soldCount: soldCount ?? this.soldCount,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    homeTeam,
    awayTeam,
    competition,
    venue,
    matchDate,
    kickoffTime,
    isOnSale,
    ticketGeneralPrice,
    ticketVipPrice,
    saleStartsAt,
    capacity,
    soldCount,
    imageUrl,
  ];
}

class RsTicket extends Equatable {
  const RsTicket({
    required this.id,
    required this.matchId,
    required this.match,
    required this.userId,
    required this.seatType,
    required this.amountPaid,
    required this.qrCode,
    required this.momoReference,
    required this.status,
    required this.purchasedAt,
  });

  final String id;
  final String matchId;
  final RsMatch match;
  final String userId;
  final SeatType seatType;
  final int amountPaid;
  final String qrCode;
  final String momoReference;
  final TicketStatus status;
  final DateTime purchasedAt;

  String get qrData {
    if (isSignedRayonTicketQr(qrCode)) {
      return qrCode;
    }

    return buildRayonTicketQrData(
      ticketId: id,
      matchId: matchId,
      purchasedAt: purchasedAt,
    );
  }

  String get matchTitle => '${match.homeTeam} vs ${match.awayTeam}';
  DateTime get matchDate => match.matchDate;
  String get competition => match.competition;
  String get venue => match.venue;
  String get kickoffTime => match.kickoffTime;
  String get fanId => userId;

  factory RsTicket.fromJson(RsJsonMap json) {
    final nestedMatch = _asMap(json['match'] ?? json['rs_matches']);
    final fallbackMatchDate = _asDateTime(json['match_date']) ?? DateTime.now();

    return RsTicket(
      id: _asString(json['id']),
      matchId: _asString(json['match_id'] ?? json['matchId']),
      match: nestedMatch.isNotEmpty
          ? RsMatch.fromJson(nestedMatch)
          : RsMatch(
              id: _asString(json['match_id'] ?? json['matchId']),
              homeTeam: _asString(
                json['home_team'] ?? json['homeTeam'],
                fallback: 'Rayon Sports FC',
              ),
              awayTeam: _asString(
                json['away_team'] ?? json['awayTeam'],
                fallback: 'Opponent',
              ),
              competition: _asString(
                json['competition'],
                fallback: 'Rwanda Premier League',
              ),
              venue: _asString(json['venue'], fallback: 'Kigali Pelé Stadium'),
              matchDate: fallbackMatchDate,
              kickoffTime: _normalizeKickoff(
                json['kickoff_time'] ?? json['kickoffTime'],
              ),
              isOnSale: _asBool(
                json['is_on_sale'] ?? json['isOnSale'],
                fallback: false,
              ),
              ticketGeneralPrice: _asInt(
                json['ticket_general_price'] ?? json['ticketGeneralPrice'],
              ),
              ticketVipPrice: _asInt(
                json['ticket_vip_price'] ?? json['ticketVipPrice'],
              ),
              saleStartsAt:
                  _asDateTime(json['sale_starts_at'] ?? json['saleStartsAt']) ??
                  fallbackMatchDate.subtract(const Duration(days: 7)),
              capacity: _asInt(json['capacity']),
            ),
      userId: _asString(json['user_id'] ?? json['userId']),
      seatType: SeatTypeX.fromValue(
        (json['seat_type'] ?? json['seatType'])?.toString(),
      ),
      amountPaid: _asInt(json['amount_paid'] ?? json['amountPaid']),
      qrCode: _asString(json['qr_code'] ?? json['qrCode']),
      momoReference: _asString(json['momo_reference'] ?? json['momoReference']),
      status: TicketStatusX.fromValue(
        (json['status'] ?? json['ticket_status'])?.toString(),
      ),
      purchasedAt:
          _asDateTime(json['purchased_at'] ?? json['purchasedAt']) ??
          DateTime.now(),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'match_id': matchId,
      'match': match.toJson(),
      'user_id': userId,
      'seat_type': seatType.value,
      'amount_paid': amountPaid,
      'qr_code': qrCode,
      'momo_reference': momoReference,
      'status': status.value,
      'purchased_at': purchasedAt.toIso8601String(),
    };
  }

  RsTicket copyWith({
    String? id,
    String? matchId,
    RsMatch? match,
    String? userId,
    SeatType? seatType,
    int? amountPaid,
    String? qrCode,
    String? momoReference,
    TicketStatus? status,
    DateTime? purchasedAt,
  }) {
    return RsTicket(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      match: match ?? this.match,
      userId: userId ?? this.userId,
      seatType: seatType ?? this.seatType,
      amountPaid: amountPaid ?? this.amountPaid,
      qrCode: qrCode ?? this.qrCode,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      purchasedAt: purchasedAt ?? this.purchasedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    matchId,
    match,
    userId,
    seatType,
    amountPaid,
    qrCode,
    momoReference,
    status,
    purchasedAt,
  ];
}
