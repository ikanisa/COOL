import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/credit_insights.dart';
import 'credit_provider.dart';

final creditInsightsProvider = FutureProvider<CreditInsights?>((ref) async {
  final repository = ref.watch(creditRepositoryProvider);
  return repository.getFinancialInsights();
});
