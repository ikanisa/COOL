import { handleMember, MemberError } from './member.mjs';

const jsonError = (code, message, status) => new Response(JSON.stringify({ ok: false, error: { code, message } }), {
  status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' },
});
export default {
  async fetch(request, env, ctx) {
    if (!new URL(request.url).pathname.startsWith('/api/member/')) return env.ASSETS?.fetch(request) ?? jsonError('not_found', 'Page not found.', 404);
    try {
      const response=await handleMember(request,env,ctx);
      if(!response)return jsonError('not_found','Action not found.',404);
      const protectedResponse=new Response(response.body,response);
      protectedResponse.headers.set('Referrer-Policy','no-referrer');
      protectedResponse.headers.set('Cross-Origin-Resource-Policy','same-origin');
      protectedResponse.headers.set('X-Content-Type-Options','nosniff');
      return protectedResponse;
    }
    catch (error) {
      if (error instanceof MemberError) return jsonError(error.code, error.message, error.status);
      // Never log credentials, email codes, receipt contents or tokenized URLs.
      return jsonError('service_unavailable', 'Collect is temporarily unavailable. Please try again.', 503);
    }
  },
  async scheduled(_event, env) {
    const time = Math.floor(Date.now() / 1000);
    await env.ADMIN_DB.batch([
      env.ADMIN_DB.prepare('DELETE FROM member_sessions WHERE refresh_until<?').bind(time),
      env.ADMIN_DB.prepare('DELETE FROM member_email_challenges WHERE expires_at<?').bind(time - 7 * 86400),
      env.ADMIN_DB.prepare('DELETE FROM member_rate_limits WHERE bucket<?').bind(Math.floor((time - 48 * 3600) / 900)),
    ]);
  },
};
