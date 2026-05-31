{{flutter_js}}
{{flutter_build_config}}

window.addEventListener('load', function () {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('custom-sw.js?v=__COLLECT_ADMIN_SW_VERSION__').catch(function (error) {
      console.warn('Collect Admin service worker registration failed:', error);
    });
  }
});

_flutter.loader.load();
