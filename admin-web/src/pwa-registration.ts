/** Register the same-origin Admin worker without taking over unfinished tabs. */
export async function registerAdminWorker(): Promise<ServiceWorkerRegistration | null> {
  if (!('serviceWorker' in navigator) || !window.isSecureContext) return null;
  try {
    return await navigator.serviceWorker.register('/custom-sw.js', {
      scope: '/',
      updateViaCache: 'none',
    });
  } catch {
    // The application remains available in a regular browser tab. The caller
    // must not claim that installation or offline access is available.
    return null;
  }
}
