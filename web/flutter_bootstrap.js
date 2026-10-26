{{flutter_js}}
{{flutter_build_config}}

var adminAssetBase = '__COLLECT_ADMIN_ASSET_BASE__';

window.addEventListener('load', function () {
  var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';
  if (
    'serviceWorker' in navigator &&
    adminServiceWorkerVersion &&
    adminServiceWorkerVersion.indexOf('__') !== 0
  ) {
    // Keep one worker URL across releases. HTTP-cache bypass applies to worker
    // updates; activation waits for all existing Admin tabs/windows to close.
    navigator.serviceWorker.register('custom-sw.js', { updateViaCache: 'none' }).catch(function (error) {
      console.warn('Collect Admin service worker registration failed:', error);
    });
  }
});

_flutter.loader.load({
  config: {
    entrypointBaseUrl: adminAssetBase,
    assetBase: adminAssetBase,
    canvasKitBaseUrl: adminAssetBase + 'canvaskit/',
  },
});
