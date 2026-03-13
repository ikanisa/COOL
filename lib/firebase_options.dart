import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase options for COOL mobile flavors.
///
/// All values must be supplied via `--dart-define` or
/// `--dart-define-from-file`.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions currentPlatformForFlavor(String flavor) {
    final options = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        flavor == 'production' ? androidProduction : androidStaging,
      TargetPlatform.iOS =>
        flavor == 'production' ? iosProduction : iosStaging,
      _ => throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for '
        '${defaultTargetPlatform.name}.',
      ),
    };

    final configurationError = _configurationErrorFor(
      options,
      platformLabel: '${defaultTargetPlatform.name}/$flavor',
    );
    if (configurationError != null) {
      throw StateError(configurationError);
    }
    return options;
  }

  static const FirebaseOptions androidProduction = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_ANDROID_PRODUCTION_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_ANDROID_PRODUCTION_APP_ID'),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID',
    ),
    projectId: String.fromEnvironment('FIREBASE_ANDROID_PRODUCTION_PROJECT_ID'),
    storageBucket: String.fromEnvironment(
      'FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET',
    ),
  );

  static const FirebaseOptions androidStaging = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_ANDROID_STAGING_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_ANDROID_STAGING_APP_ID'),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_ANDROID_STAGING_MESSAGING_SENDER_ID',
    ),
    projectId: String.fromEnvironment('FIREBASE_ANDROID_STAGING_PROJECT_ID'),
    storageBucket: String.fromEnvironment(
      'FIREBASE_ANDROID_STAGING_STORAGE_BUCKET',
    ),
  );

  static const FirebaseOptions iosProduction = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_IOS_PRODUCTION_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_IOS_PRODUCTION_APP_ID'),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID',
    ),
    projectId: String.fromEnvironment('FIREBASE_IOS_PRODUCTION_PROJECT_ID'),
    storageBucket: String.fromEnvironment(
      'FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET',
    ),
    iosBundleId: String.fromEnvironment('FIREBASE_IOS_PRODUCTION_BUNDLE_ID'),
  );

  static const FirebaseOptions iosStaging = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_IOS_STAGING_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_IOS_STAGING_APP_ID'),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_IOS_STAGING_MESSAGING_SENDER_ID',
    ),
    projectId: String.fromEnvironment('FIREBASE_IOS_STAGING_PROJECT_ID'),
    storageBucket: String.fromEnvironment(
      'FIREBASE_IOS_STAGING_STORAGE_BUCKET',
    ),
    iosBundleId: String.fromEnvironment('FIREBASE_IOS_STAGING_BUNDLE_ID'),
  );

  static String? _configurationErrorFor(
    FirebaseOptions options, {
    required String platformLabel,
  }) {
    if (options.apiKey.trim().isEmpty ||
        options.appId.trim().isEmpty ||
        options.messagingSenderId.trim().isEmpty ||
        options.projectId.trim().isEmpty ||
        (options.storageBucket?.trim().isEmpty ?? true) ||
        (defaultTargetPlatform == TargetPlatform.iOS &&
            (options.iosBundleId?.trim().isEmpty ?? true))) {
      return 'Firebase config for $platformLabel is incomplete. Provide all '
          'required FIREBASE_* values via --dart-define-from-file.';
    }
    return null;
  }
}
