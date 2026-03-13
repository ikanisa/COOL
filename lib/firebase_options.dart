import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase options for COOL mobile flavors.
///
/// Generated from the active Firebase project state on 2026-03-12 and kept
/// explicit so Android/iOS staging and production resolve deterministically.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions currentPlatformForFlavor(String flavor) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return flavor == 'production' ? androidProduction : androidStaging;
      case TargetPlatform.iOS:
        return flavor == 'production' ? iosProduction : iosStaging;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for '
          '${defaultTargetPlatform.name}.',
        );
    }
  }

  static const FirebaseOptions androidProduction = FirebaseOptions(
    apiKey: 'AIzaSyBZWg0JT-v2Qpirp63RbsPqzB4JY2onfJw',
    appId: '1:1074154147498:android:8469cac3e0217113dc4ad3',
    messagingSenderId: '1074154147498',
    projectId: 'gen-lang-client-0172279957',
    storageBucket: 'gen-lang-client-0172279957.firebasestorage.app',
  );

  static const FirebaseOptions androidStaging = FirebaseOptions(
    apiKey: 'AIzaSyBZWg0JT-v2Qpirp63RbsPqzB4JY2onfJw',
    appId: '1:1074154147498:android:6402a2d270edd059dc4ad3',
    messagingSenderId: '1074154147498',
    projectId: 'gen-lang-client-0172279957',
    storageBucket: 'gen-lang-client-0172279957.firebasestorage.app',
  );

  static const FirebaseOptions iosProduction = FirebaseOptions(
    apiKey: 'AIzaSyC3wczTXHP3fkryFydOTu6RIbxZ5vRUbg0',
    appId: '1:1074154147498:ios:97b9701b34e0dddedc4ad3',
    messagingSenderId: '1074154147498',
    projectId: 'gen-lang-client-0172279957',
    storageBucket: 'gen-lang-client-0172279957.firebasestorage.app',
    iosBundleId: 'app.cool.mobile',
  );

  static const FirebaseOptions iosStaging = FirebaseOptions(
    apiKey: 'AIzaSyC3wczTXHP3fkryFydOTu6RIbxZ5vRUbg0',
    appId: '1:1074154147498:ios:59411d4546071204dc4ad3',
    messagingSenderId: '1074154147498',
    projectId: 'gen-lang-client-0172279957',
    storageBucket: 'gen-lang-client-0172279957.firebasestorage.app',
    iosBundleId: 'app.cool.mobile.staging',
  );
}
