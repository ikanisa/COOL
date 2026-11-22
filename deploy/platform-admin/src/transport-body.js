import {ProxyFailure, refuse} from './transport-failure.js';

// A stream implementation may reject or never finish cancellation. Observe the
// outcome without letting it hold an already-refused request open.
export function cancelObserved(target) {
  try { const pending = target?.cancel(); if (pending !== undefined) void Promise.resolve(pending).catch(() => {}); } catch {}
}
export async function boundedBytes(stream, limit, signal, status, code) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader(); let bytes = new Uint8Array(); let total = 0;
  const abort = () => cancelObserved(reader);
  signal.addEventListener('abort', abort, {once: true});
  try {
    while (true) {
      if (signal.aborted) refuse(504, 'proxy_deadline');
      const {done, value} = await reader.read(); if (done) break;
      if (!(value instanceof Uint8Array)) { cancelObserved(reader); throw new TypeError('Invalid stream chunk'); }
      const length = value.byteLength;
      if (length > limit - total) { cancelObserved(reader); refuse(status, code); }
      if (length === 0) continue;
      const needed = total + length;
      if (needed > bytes.byteLength) {
        const capacity = Math.min(limit, Math.max(needed, bytes.byteLength ? bytes.byteLength * 2 : 1024));
        const grown = new Uint8Array(capacity); grown.set(bytes.subarray(0, total)); bytes = grown;
      }
      bytes.set(value, total); total = needed;
    }
    if (signal.aborted) refuse(504, 'proxy_deadline');
    return bytes.subarray(0, total);
  } finally { signal.removeEventListener('abort', abort); reader.releaseLock(); }
}

/** Stop waiting at the deadline even if the host fetch does not settle on abort. */
export async function fetchWithinDeadline(request, signal, fetchImpl) {
  let onAbort;
  try {
    return await new Promise((resolve, reject) => {
      onAbort = () => reject(new ProxyFailure(504, 'proxy_deadline'));
      signal.addEventListener('abort', onAbort, {once: true});
      Promise.resolve(fetchImpl(request)).then(response => {
        if (signal.aborted) cancelObserved(response?.body);
        else resolve(response);
      }).catch(reject);
    });
  } finally {
    signal.removeEventListener('abort', onAbort);
  }
}
