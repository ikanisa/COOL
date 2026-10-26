import 'payment_help_storage_contract.dart';
import 'payment_help_storage_native.dart'
    if (dart.library.js_interop) 'payment_help_storage_web.dart'
    as platform;

export 'payment_help_storage_contract.dart';

PaymentHelpProtectedStorage createPaymentHelpStorage() =>
    platform.createStore();
