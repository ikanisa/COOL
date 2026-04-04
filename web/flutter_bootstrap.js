{{flutter_js}}
{{flutter_build_config}}

window._coolServiceWorkerVersion = {{flutter_service_worker_version}};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: window._coolServiceWorkerVersion,
    serviceWorkerUrl: `custom-sw.js?v=${window._coolServiceWorkerVersion}`,
  },
});
