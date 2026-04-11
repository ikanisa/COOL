const ROOT_CACHE_CONTROL = 'public, max-age=300, must-revalidate';

const ROOT_SECURITY_HEADERS = {
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Permissions-Policy':
    'camera=(), microphone=(), geolocation=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=(), fullscreen=(self)',
  'Content-Security-Policy':
    "default-src 'self'; base-uri 'self'; connect-src 'self'; font-src 'self' https://fonts.gstatic.com data:; frame-ancestors 'none'; img-src 'self' data:; manifest-src 'self'; object-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; worker-src 'self'; form-action 'self'; upgrade-insecure-requests",
};

function withRootHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set('Cache-Control', ROOT_CACHE_CONTROL);

  for (const [name, value] of Object.entries(ROOT_SECURITY_HEADERS)) {
    headers.set(name, value);
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export async function onRequest(context) {
  const url = new URL(context.request.url);

  if (url.pathname === '/' || url.pathname === '') {
    url.pathname = '/admin/';
  }

  const assetRequest =
    url.toString() === context.request.url
      ? context.request
      : new Request(url.toString(), context.request);

  const response = await context.env.ASSETS.fetch(assetRequest);
  return withRootHeaders(response);
}
