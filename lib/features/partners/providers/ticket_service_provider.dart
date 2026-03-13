import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/hive_providers.dart';
import '../services/ticket_service.dart';

/// Central [TicketService] provider.
///
/// All call sites that previously used `TicketService.instance` should
/// instead obtain the service through this provider.
final ticketServiceProvider = Provider<TicketService>((ref) {
  return TicketService(openBox: ref.read(hiveStringBoxProvider));
});
