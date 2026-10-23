import {validateAdminOrigin} from '../admin-security.js';
import {issueAdminSession} from './admin_accounts.js';
import {startGoogleFlow,exchangeGoogleFlow} from './google_auth.js';

/** Google proves managed identity only. Existing approved staff admission owns
 * roles, principal mapping, exact session lifetime, MFA and the opaque cookie. */
export async function handleAdminGoogle(request,env) {
 const path=new URL(request.url).pathname;
 if(!['/api/admin/auth/google/start','/api/admin/auth/google/exchange'].includes(path))return null;
 validateAdminOrigin(request,env);
 if(path.endsWith('/start'))return startGoogleFlow(request,env,{surface:'admin'});
 return exchangeGoogleFlow(request,env,{surface:'admin',admit:issueAdminSession});
}
