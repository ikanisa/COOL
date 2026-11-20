import legacyEntry from '../src/index.mjs';
import {handoffScript, SCRIPT_PATH} from '../src/handoff.mjs';

const PAGES_ORIGIN = 'https://cool-admin-212.pages.dev';
const SHARED_ENTRY_HOST = 'admin.collect.ikanisa.com';
const PRODUCTION = 'https://platform-admin.collect.ikanisa.com';

// The deployed Flutter router included these resource families. React has no
// matching route or guaranteed identity mapping for those old record IDs.
// Leave the original address open with the existing separate-tab home link.
function hasRetiredBookmark() {
  const former = /^\/admin\/(?:allocations|audit-logs|denied|exceptions|feature-flags|ledger|payment-events|payment-intents|receivers|settings|sms|system-health)(?:[/?#]|$)/i;
  return former.test(window.location.pathname) || former.test(window.location.hash.slice(1));
}

export default {
  fetch(request) {
    const url = new URL(request.url);
    if (url.origin !== PAGES_ORIGIN) {
      return new Response(null, {status:403, headers:{'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
    }
    // Only the local dispatch key changes. The shared handler reads the method,
    // path and headers without fetching an upstream or accessing the request body.
    url.hostname = SHARED_ENTRY_HOST;
    const response = legacyEntry.fetch({url:url.href, method:request.method, headers:request.headers});
    if (url.pathname !== SCRIPT_PATH || response.status !== 200 || request.method !== 'GET') return response;
    // A second bookmark can change only the fragment of this handoff document.
    // Reload that same document on an explicit bookmark change so its storage,
    // cookie and route checks run again. Installed Flutter tabs never load it.
    const script = `window.addEventListener('hashchange', () => window.location.reload());\nif (!(${hasRetiredBookmark.toString()})()) {\n${handoffScript(PRODUCTION)}\n}`;
    return new Response(script, {headers:response.headers});
  },
};
