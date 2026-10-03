import 'dart:convert';
import 'dart:io';
import '../../lib/admin/core/admin_exception_models.dart';
import '../../lib/admin/core/admin_receipt_deferral_models.dart';

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Actual SQL fixture directory required');
  Map<String, dynamic> observed(String name) => Map<String, dynamic>.from(
    jsonDecode(File('${args.single}/observed-busy-admin-$name.json').readAsStringSync()) as Map,
  );
  var count = 0;
  void check(String name, bool accepted) {
    if (!accepted) throw StateError(name);
    count++; stdout.writeln('PASS $name');
  }
  final detail = observed('detail');
  final id = detail['exception_id'] as String;
  final evidence = AdminReceiptDeferralEvidence.parse(detail, id);
  check('actual SQL busy detail has distinct deferred unhandled labels',
    evidence.disposition == 'deferred' && !evidence.businessHandled &&
    evidence.currentCode == 'SOURCE_BUSY' && evidence.originalCode == 'SOURCE_BUSY' &&
    evidence.currentLabel == 'Receipt source is busy' && evidence.originalLabel == 'Receipt source is busy' &&
    evidence.receiptId == null);
  final inbox = observed('inbox');
  final row = (inbox['rows'] as List).cast<Map<String, dynamic>>().singleWhere((r) => r['id'] == id);
  final parsed = AdminExceptionRow.parse(row, exceptionInstant(inbox['checked_at']));
  check('actual exception inbox parses the closed SOURCE_BUSY reason',
    parsed.source == AdminExceptionSource.receiptEvent && parsed.reasonLabel == 'Receipt source is busy');
  void refused(String name, Map<String, dynamic> patch) {
    var denied = false;
    try {AdminReceiptDeferralEvidence.parse({...detail, ...patch}, id);} on FormatException {denied = true;}
    check(name, denied);
  }
  refused('busy detail cannot fabricate business handling', {'business_handled': true});
  refused('busy detail cannot invent a finite code', {'current_code': 'SOURCE_BUSY_UNKNOWN'});
  refused('busy detail cannot invent a receipt identifier', {'receipt_id': '99780000-0000-4000-8000-000000050003'});
  refused('busy detail cannot add private destination fields', {'destination': '+250788000000'});
  refused('busy detail cannot claim a financial side effect', {'financial_action': true});
  stdout.writeln('PASS $count distinct actual Admin model checks');
}
