package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release builds do not ship the integration_test Android plugin, but the
 * generated plugin registrant still references it after running device-backed
 * tests. A no-op release stub keeps production flavor builds compiling while
 * debug/device-test builds continue to use the real plugin from Flutter.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
