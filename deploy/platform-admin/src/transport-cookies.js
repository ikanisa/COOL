import {refuse} from './transport-failure.js';

const ADMIN_COOKIE = '__Host-collect_admin';
const MANAGED_ADMIN_COOKIE = '__Host-collect_admin_rrlduytparvsjfmegalh';

function cookiesOf(headers) {
  // Workers exposes getAll(Set-Cookie); Node exposes getSetCookie. Never use
  // comma splitting alone: an Expires date contains a comma too.
  const values = typeof headers.getSetCookie === 'function' ? headers.getSetCookie() :
    typeof headers.getAll === 'function' ? headers.getAll('Set-Cookie') :
    headers.has('set-cookie') ? [headers.get('set-cookie')] : [];
  if (!Array.isArray(values) || values.some(value => typeof value !== 'string') ||
      values.reduce((total, value) => total + value.length, 0) > 16384) refuse(502, 'proxy_cookie_invalid');
  const cookies = values.flatMap(value => value.split(/,(?=\s*[!#$%&'*+.^_`|~0-9A-Za-z-]+=)/).map(part => part.trim()));
  if (cookies.length > 8 || cookies.some(value => !value || value.length > 4096 || /[\x00-\x1f\x7f]/.test(value))) refuse(502, 'proxy_cookie_invalid');
  return cookies;
}
function gatewayCookie(cookie) {
  const pieces = cookie.split(';').map(value => value.trim());
  if (!/^(?:__cf_bm|_cfuvid)=/.test(pieces[0])) return false;
  // These cookies belong to the fixed Supabase gateway, never the frontend.
  // Validate their boundaries before discarding so a folded app cookie cannot
  // be swallowed along with an infrastructure cookie.
  if (!/^(?:__cf_bm|_cfuvid)=[^\s,;"\\]*$/.test(pieces[0]) || pieces.slice(1).some(value =>
    !/^[A-Za-z0-9_-]+(?:=[^\x00-\x1f;]*)?$/.test(value) ||
    value.includes(',') && !/^expires=[A-Za-z]{3}, \d{2} [A-Za-z]{3} \d{4} \d{2}:\d{2}:\d{2} GMT$/i.test(value))) refuse(502, 'proxy_cookie_invalid');
  return true;
}
function validateCookie(cookie, route) {
  if (route.functionName !== 'admin-api' || cookie.length > 4096 || /[\r\n]/.test(cookie)) refuse(502, 'proxy_cookie_invalid');
  const pieces = cookie.split(';').map(value => value.trim());
  if (!/^__Host-collect_admin=[A-Za-z0-9_-]*$/.test(pieces[0])) refuse(502, 'proxy_cookie_invalid');
  const attrs = new Map();
  for (const attribute of pieces.slice(1)) {
    const split = attribute.indexOf('=');
    const name = (split < 0 ? attribute : attribute.slice(0, split)).trim().toLowerCase();
    if (!name || attrs.has(name)) refuse(502, 'proxy_cookie_invalid');
    attrs.set(name, split < 0 ? null : attribute.slice(split + 1).trim().toLowerCase());
  }
  if (attrs.has('domain') || !attrs.has('secure') || attrs.get('secure') !== null ||
      !attrs.has('httponly') || attrs.get('httponly') !== null || attrs.get('path') !== '/' ||
      !['strict', 'lax'].includes(attrs.get('samesite'))) refuse(502, 'proxy_cookie_invalid');
}
export function managedBrowserCookies(headers, route) {
  const cookies = (headers.get('Cookie') ?? '').split(';').map(cookie => cookie.trim());
  headers.delete('Cookie');
  if (route.functionName !== 'admin-api') return;
  const managed = cookies.filter(cookie => cookie.startsWith(MANAGED_ADMIN_COOKIE + '='));
  if (!managed.length) return;
  const value = managed[0].slice(MANAGED_ADMIN_COOKIE.length + 1);
  if (managed.length !== 1 || !/^[A-Za-z0-9_-]{1,4096}$/.test(value)) refuse(400, 'proxy_cookie_invalid');
  headers.set('Cookie', ADMIN_COOKIE + '=' + value);
}

export function forwardResponseCookie(upstream, headers, route, isolateAdminSession) {
  const cookies = cookiesOf(upstream.headers).filter(cookie => !gatewayCookie(cookie));
  if (cookies.length > 1) refuse(502, 'proxy_cookie_invalid');
  for (const cookie of cookies) {
    validateCookie(cookie, route);
    const value = isolateAdminSession ? MANAGED_ADMIN_COOKIE + cookie.slice(ADMIN_COOKIE.length) : cookie;
    headers.append('Set-Cookie', value);
  }
}
