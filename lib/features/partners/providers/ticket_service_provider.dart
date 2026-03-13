import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/ticket_service.dart';

/// Central [TicketService] provider.
///
/// All call sites that previously used `TicketService.instance` should
/// instead obtain the service through this provider.
final ticketServiceProvider = Provider<TicketService>((ref) {
  return TicketService(openBox: Hive.openBox<String>);
});
