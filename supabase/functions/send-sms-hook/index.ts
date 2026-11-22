import {createCollectSendSmsHandler} from '../_shared/send-sms-hook.js';

// This endpoint uses Supabase Auth's Standard Webhooks HMAC over the exact
// request body. It does not accept user JWTs, browser origins or API keys as
// inbound authority, and it cannot generate or verify an OTP.
Deno.serve(createCollectSendSmsHandler());
