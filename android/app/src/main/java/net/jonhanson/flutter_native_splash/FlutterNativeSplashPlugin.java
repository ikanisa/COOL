package net.jonhanson.flutter_native_splash;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-build shim for the flutter_native_splash dev dependency.
 *
 * The package is used only to generate native splash assets, but some
 * Flutter/Gradle paths still emit a registrant entry for its Android plugin
 * class. Providing a no-op implementation keeps production builds compiling
 * without affecting runtime behavior.
 */
public final class FlutterNativeSplashPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
