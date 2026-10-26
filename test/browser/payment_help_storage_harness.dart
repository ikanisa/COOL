// Standalone browser harness for the actual protected-storage adapter. Compile
// with dart compile js and run scripts/qa/payment_help_storage_browser.cjs.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:collect_app/shared/repositories/payment_help_storage_web.dart';

@JS('paymentHelpWebCall')
external set _call(JSFunction function);

void main() {
  final storage = WebPaymentHelpProtectedStorage();
  _call = ((JSString operation, JSString ownerId, JSString input) {
    return (() async {
      try {
        final owner = ownerId.toDart;
        final value = input.toDart;
        final String? result;
        switch (operation.toDart) {
          case 'read':
            result = await storage.read(owner);
          case 'write':
            await storage.write(owner, value);
            result = null;
          case 'clear':
            await storage.clear(owner);
            result = null;
          case 'claim':
            result = await storage.exclusive(() async {
              final existing = await storage.read(owner);
              if (existing != null) return existing;
              await Future<void>.delayed(const Duration(milliseconds: 120));
              await storage.write(owner, value);
              return value;
            });
          default:
            throw StateError('Unknown harness operation');
        }
        return jsonEncode({'ok': true, 'value': result}).toJS;
      } catch (error) {
        return jsonEncode({
          'ok': false,
          'type': error.runtimeType.toString(),
          'error': error.toString(),
        }).toJS;
      }
    })().toJS;
  }).toJS;
}
