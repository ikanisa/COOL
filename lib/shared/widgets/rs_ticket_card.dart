import 'package:flutter/material.dart';

import '../../features/partners/rayon/models/rs_models.dart';
import 'rs_digital_ticket.dart';

class RsTicketCard extends StatelessWidget {
  const RsTicketCard({required this.ticket, this.isExpanded = true, super.key});

  final RsTicket ticket;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    return RsDigitalTicket(ticket: ticket, isExpanded: isExpanded);
  }
}
