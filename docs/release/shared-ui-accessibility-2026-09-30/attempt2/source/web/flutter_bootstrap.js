{{flutter_js}}
{{flutter_build_config}}

window.addEventListener('load', function () {
  var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';
  if (
    'serviceWorker' in navigator &&
    adminServiceWorkerVersion &&
    adminServiceWorkerVersion.indexOf('__') !== 0
  ) {
    navigator.serviceWorker.register('custom-sw.js?v=' + adminServiceWorkerVersion).catch(function (error) {
      console.warn('Collect Admin service worker registration failed:', error);
    });
  }
});

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
