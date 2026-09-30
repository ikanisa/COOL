import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_reconciliation_models.dart';

void main() {
  const review = '99920000-0000-4000-8000-000000000004';
  const payment = '99920000-0000-4000-8000-000000000003';
  final wire = <String, dynamic>{
    'review_id': review,
    'payment_id': payment,
    'payment_status': 'posted',
    'replayed': false,
    'evidence_level': 'independently_reconciled',
    'unexpected_sensitive_context': 'synthetic-only',
  };
  var rejected = false;
  try {
    AdminReconciliationFinalization.fromJson(
      wire,
      reviewId: review,
      paymentId: payment,
    );
  } on FormatException {
    rejected = true;
  }
  stdout.writeln(
    jsonEncode({
      'probe': 'exact five-field reconciliation final ACK',
      'unexpected_field_rejected': rejected,
      'database_called': false,
      'provider_called': false,
    }),
  );
  if (!rejected) exitCode = 1;
}
