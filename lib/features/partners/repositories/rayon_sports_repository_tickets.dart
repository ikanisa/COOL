part of 'rayon_sports_repository.dart';

extension RayonSportsTicketRepository on RayonSportsRepository {
  Future<List<RsMatch>> getMatches(String partnerId, bool onSaleOnly) async {
    var query = _client.from('rs_matches').select().eq('partner_id', partnerId);

    if (onSaleOnly) {
      query = query.eq('is_on_sale', true);
    }

    return _asListOfMaps(
      await query.order('match_date'),
    ).map(RsMatch.fromJson).toList(growable: false);
  }

  Future<List<RsTicket>> purchaseTickets({
    required String matchId,
    required String userId,
    required String seatType,
    required int quantity,
    String? referralInviteId,
  }) async {
    final match = _asListOfMaps(
      await _client.from('rs_matches').select().eq('id', matchId),
    ).map(RsMatch.fromJson).first;

    final normalizedSeat = seatType.toLowerCase() == 'vip' ? 'VIP' : 'General';
    final unitPrice = normalizedSeat == 'VIP'
        ? match.ticketVipPrice
        : match.ticketGeneralPrice;

    final totalAmount = unitPrice * quantity;
    return _checkoutService.openCheckout(
      component: 'rayon_ticket',
      userId: userId,
      referencePrefix: 'RS-TICKET',
      amount: totalAmount,
      successMessage: 'Rayon ticket checkout opened successfully.',
      failureMessage: 'Rayon ticket checkout failed before payment sync.',
      failureMetadata: <String, Object?>{
        'match_id': matchId,
        'quantity': quantity,
        'seat_type': normalizedSeat,
        'amount': totalAmount,
      },
      prepare: (paymentReference) async {
        final inserts = <Map<String, Object?>>[];
        for (var i = 0; i < quantity; i++) {
          inserts.add(<String, Object?>{
            'match_id': matchId,
            'user_id': userId,
            'seat_type': normalizedSeat,
            'amount_paid': unitPrice,
            'qr_code': null,
            'momo_reference': paymentReference,
            'referral_invite_id': referralInviteId,
            'status': 'pending',
          });
        }

        final rows = _asListOfMaps(
          await _client.from('rs_tickets').insert(inserts).select(),
        );

        final tickets = rows
            .map((row) {
              final ticket = RsTicket.fromJson(<String, Object?>{
                ...row,
                'match': match.toJson(),
              });
              return ticket.copyWith(qrCode: _ticketQrCodeFor(ticket));
            })
            .toList(growable: false);

        return RayonCheckoutResult<List<RsTicket>>(
          value: tickets,
          subjectType: 'rs_tickets',
          subjectId: tickets.isEmpty ? null : tickets.first.id,
          successMetadata: <String, Object?>{
            'match_id': matchId,
            'quantity': quantity,
            'seat_type': normalizedSeat,
            'amount': totalAmount,
          },
        );
      },
    );
  }

  Future<List<RsTicket>> getMyTickets(String userId) async {
    final ticketRows = _asListOfMaps(
      await _client
          .from('rs_tickets')
          .select()
          .eq('user_id', userId)
          .order('purchased_at', ascending: false),
    );

    if (ticketRows.isEmpty) return const [];

    final matchIds = ticketRows
        .map((r) => r['match_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final matchRows = _asListOfMaps(
      await _client.from('rs_matches').select().inFilter('id', matchIds),
    );
    final matchesById = <String, RsMatch>{
      for (final m in matchRows.map(RsMatch.fromJson)) m.id: m,
    };

    return ticketRows
        .map((row) {
          final match = matchesById[row['match_id']?.toString()];
          return RsTicket.fromJson(<String, Object?>{
            ...row,
            'match': match?.toJson(),
          });
        })
        .toList(growable: false);
  }

  Future<void> cancelTicket(String ticketId) async {
    await _client
        .from('rs_tickets')
        .update(<String, Object?>{'status': 'cancelled'})
        .eq('id', ticketId)
        .eq('status', 'pending');
  }

  Future<String> createGoogleWalletSaveUrl({required String ticketId}) async {
    final response = await _client.functions.invoke(
      'wallet-issuer',
      body: <String, Object?>{'action': 'rayon_ticket', 'ticketId': ticketId},
    );

    final data = _asMap(response.data);
    if (data['success'] != true) {
      throw StateError(
        data['message']?.toString() ??
            'Failed to prepare the Google Wallet pass.',
      );
    }

    final saveUrl = data['saveUrl']?.toString().trim() ?? '';
    if (saveUrl.isEmpty) {
      throw StateError('Wallet issuer did not return a save URL.');
    }

    return saveUrl;
  }
}
