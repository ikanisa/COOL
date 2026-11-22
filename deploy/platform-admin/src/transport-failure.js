export class ProxyFailure extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
export function refuse(status, code) { throw new ProxyFailure(status, code); }

export function protectedHeaders(headers = new Headers()) {
  headers.set('Cache-Control', 'private, no-store, max-age=0');
  headers.set('CDN-Cache-Control', 'no-store');
  headers.set('Surrogate-Control', 'no-store');
  headers.set('Pragma', 'no-cache');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return headers;
}
export function failure(status, code, reason) {
  const headers = protectedHeaders(); headers.set('Content-Type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify({code, ...(reason ? {reason} : {})}), {status, headers});
}
