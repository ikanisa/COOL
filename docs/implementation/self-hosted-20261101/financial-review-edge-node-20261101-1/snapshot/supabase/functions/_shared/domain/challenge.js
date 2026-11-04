import {ApiError} from './core.js';
const TYPE='collect.turnstile.v1';
export async function challengeRoute(request,env) {
 const url=new URL(request.url);
 if(url.pathname!=='/v1/security/challenge'||request.method!=='GET')return null;
 const siteKey=env.TURNSTILE_SITE_KEY;
 if(typeof siteKey!=='string'||!/^[A-Za-z0-9_-]{10,256}$/.test(siteKey))throw new ApiError(503,'verification_unavailable','Verification is unavailable. Please try again later.');
 const attempt=url.searchParams.get('attempt_id');
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(attempt??''))throw new ApiError(400,'invalid_attempt','Reopen verification before continuing.');
 const parent=url.searchParams.get('parent_origin')??url.origin;
 const allowed=new Set([url.origin,...[env.ALLOWED_ORIGINS??'',env.ADMIN_ORIGINS??env.ADMIN_ORIGIN??''].join(',').split(',').map(s=>s.trim()).filter(Boolean)]);
 if(!allowed.has(parent))throw new ApiError(403,'origin_denied','This verification origin is unavailable.');
 const theme=url.searchParams.get('theme')??'auto';
 if(!['light','dark','auto'].includes(theme))throw new ApiError(400,'invalid_theme','Invalid verification appearance.');
 const nonce=crypto.randomUUID();
 const settings=JSON.stringify({type:TYPE,attempt_id:attempt,parent_origin:parent,site_key:siteKey,theme,action:'collect-login'}).replace(/</g,'\\u003c');
 const html=`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Verify your request · Collect</title><style nonce="${nonce}">:root{color-scheme:light dark}body{margin:0;padding:24px;font:400 1rem/1.5 system-ui,sans-serif;color:CanvasText;background:Canvas}h1{font-size:1.5rem;line-height:1.3;margin:0 0 12px}p{margin:0 0 20px;max-width:40ch}#challenge{min-height:80px}#status{margin-top:16px}button{font:inherit;padding:12px 24px;border-radius:24px;border:1px solid currentColor;color:inherit;background:transparent;cursor:pointer}button:focus-visible{outline:3px solid Highlight;outline-offset:3px}@media(prefers-reduced-motion:no-preference){button{transition:opacity .15s}}@media(max-width:360px){body{padding:16px}}</style></head><body><main><h1>Verify your request</h1><p>Complete this check to continue signing in.</p><div id="challenge"></div><p id="status" role="status" aria-live="polite">Loading verification…</p><button id="retry" hidden>Try again</button></main><script nonce="${nonce}">
 const config=${settings};let widget=null;let accepted=false;let latestMessage=null;
 const status=document.getElementById('status'),retry=document.getElementById('retry');
 function deliver(message){const text=JSON.stringify(message);
  if(window.CollectTurnstile&&typeof window.CollectTurnstile.postMessage==='function')window.CollectTurnstile.postMessage(text);
  else if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.CollectTurnstile)window.webkit.messageHandlers.CollectTurnstile.postMessage(text);
  else window.parent.postMessage(message,config.parent_origin);
 }
 function emit(extra){latestMessage={type:config.type,attempt_id:config.attempt_id,...extra};deliver(latestMessage);}
 document.addEventListener('collect.turnstile.ready',()=>{if(latestMessage)deliver(latestMessage);});
 function failed(code){accepted=false;status.textContent=code==='expired'?'Verification expired. Try again.':'Verification is unavailable. Try again.';retry.hidden=false;emit({error:code});}
 window.collectChallengeReady=function(){widget=turnstile.render('#challenge',{sitekey:config.site_key,action:config.action,theme:config.theme,
  callback:function(token){if(accepted)return;if(typeof token!=='string'||token.length<1||token.length>2048){failed('invalid_token');return;}accepted=true;retry.hidden=true;status.textContent='Verification complete. Return to sign-in.';emit({token});},
  'error-callback':function(){failed('unavailable');},'expired-callback':function(){failed('expired');},'timeout-callback':function(){failed('timeout');}});status.textContent='Complete verification to continue.';};
 retry.addEventListener('click',()=>{accepted=false;retry.hidden=true;status.textContent='Loading verification…';if(widget!==null&&window.turnstile)turnstile.reset(widget);else location.reload();});
 </script><script nonce="${nonce}" src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=collectChallengeReady&amp;render=explicit" async defer></script></body></html>`;
 return new Response(html,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
  'Content-Security-Policy':`default-src 'none'; script-src 'nonce-${nonce}' https://challenges.cloudflare.com; style-src 'nonce-${nonce}'; frame-src https://challenges.cloudflare.com; connect-src https://challenges.cloudflare.com; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'self' ${(env.ALLOWED_ORIGINS??'').split(',').map(s=>s.trim()).filter(Boolean).join(' ')}`}});
}
