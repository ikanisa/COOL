import {createRoot} from 'react-dom/client';
import {AdminApp} from './app/App';
import {readAdminConfig} from './config';
import {hasPredecessorCustody} from './custodyRealm';
import {registerAdminWorker} from './pwa-registration';
import {captureSetupLocation, SessionProvider} from './session/SessionProvider';
import './styles/admin.css';

// Capture and erase one-use setup tokens before constructing a router or page.
const setup = captureSetupLocation();
if (!window.location.hash && (window.location.pathname === '/admin' ||
    (window.location.pathname.startsWith('/admin/') && !window.location.pathname.startsWith('/admin/auth/local-challenge')))) {
  // Existing path-style entries join the established hash-route form without
  // decoding nested query values into new route delimiters.
  window.history.replaceState(null, '', `/#${window.location.pathname}${window.location.search}`);
}

const root = document.getElementById('root');
if (!root) throw new Error('The Admin workspace cannot start.');
const renderer = createRoot(root);
try {
  const config = readAdminConfig(import.meta.env, window.location.origin);
  // A session lookup may refresh or revoke custody; avoid a development-only
  // StrictMode remount that would automatically repeat it.
  renderer.render(<>{hasPredecessorCustody() && <aside role="note" className="admin-previous-service">
    If you have unfinished work from the previous Admin service, keep its original tab open.
    Ask your administrator to check the original request before submitting it again.
  </aside>}<SessionProvider config={config}><AdminApp setup={setup} /></SessionProvider></>);
  if (import.meta.env.PROD) void registerAdminWorker();
} catch {
  renderer.render(<main className="admin-state" role="alert"><h1>Workspace unavailable</h1>
    <p>The workspace could not be opened. Contact your administrator.</p></main>);
}
