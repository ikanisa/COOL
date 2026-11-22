const MAX_RESPONSE_BYTES = 2_000_000;
const MAX_READS = 16_384;
const PASSTHROUGH_HEADERS = new Set(['content-type', 'content-disposition', 'retry-after', 'x-request-id']);
export const RESPONSE_SAFETY_HEADERS = {
  'cache-control': 'private, no-store, no-transform',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
};

async function responseBytes(body, signal) {
  if (!body) return new Uint8Array();
  const reader = body.getReader();
  const chunks = [];
  let size = 0;
  let reads = 0;
  let completed = false;
  let pendingReject = null;
  const cancel = () => {
    try { void reader.cancel().catch(() => {}); } catch {}
  };
  const onAbort = () => {
    pendingReject?.(Error('response_timeout'));
    cancel();
  };
  signal.addEventListener('abort', onAbort, {once: true});
  try {
    while (true) {
      if (signal.aborted) throw Error('response_timeout');
      if (++reads > MAX_READS) throw Error('response_complexity');
      const part = await new Promise((resolve, reject) => {
        pendingReject = reject;
        if (signal.aborted) {
          onAbort();
          return;
        }
        reader.read().then(value => {
          pendingReject = null;
          resolve(value);
        }, error => {
          pendingReject = null;
          reject(error);
        });
      });
      if (signal.aborted) throw Error('response_timeout');
      if (part.done) {
        completed = true;
        break;
      }
      if (!(part.value instanceof Uint8Array)) throw Error('response_limit');
      size += part.value.byteLength;
      if (size > MAX_RESPONSE_BYTES) throw Error('response_limit');
      chunks.push(part.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return bytes;
  } finally {
    pendingReject = null;
    signal.removeEventListener('abort', onAbort);
    if (!completed) cancel();
    try { reader.releaseLock(); } catch {}
  }
}

export async function admitUpstreamResponse(response, signal) {
  const {status, headers} = response;
  if (status < 200 || (status >= 300 && status < 400) || status > 599) return null;
  const type = (headers.get('content-type') ?? '').split(';', 1)[0].trim().toLowerCase();
  const encoding = (headers.get('content-encoding') ?? '').toLowerCase();
  if (!['application/json', 'text/csv'].includes(type) || !['', 'identity'].includes(encoding)) return null;

  const declared = headers.get('content-length');
  if (declared !== null && (!/^(0|[1-9][0-9]{0,7})$/.test(declared) || Number(declared) > MAX_RESPONSE_BYTES)) return null;
  const bytes = await responseBytes(response.body, signal);
  if (declared !== null && Number(declared) !== bytes.length) return null;

  const resultHeaders = new Headers(RESPONSE_SAFETY_HEADERS);
  for (const [name, value] of headers) {
    if (PASSTHROUGH_HEADERS.has(name) || name.startsWith('x-burimunsi-')) resultHeaders.set(name, value);
  }
  return new Response([204, 205, 304].includes(status) ? null : bytes, {status, headers: resultHeaders});
}
