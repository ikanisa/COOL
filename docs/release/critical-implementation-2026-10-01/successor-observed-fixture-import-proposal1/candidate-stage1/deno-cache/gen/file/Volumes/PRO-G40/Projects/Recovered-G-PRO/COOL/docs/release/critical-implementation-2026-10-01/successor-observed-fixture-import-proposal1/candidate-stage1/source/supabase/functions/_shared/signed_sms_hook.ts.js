import { PublicError, boundedBody, objectValue } from './production_contract.ts';
/** Standard Webhooks v1 HMAC-SHA256. Persistent id replay control is separate. */ export async function verifySmsHook(request, secrets, now = Math.floor(Date.now() / 1000)) {
  const id = request.headers.get('webhook-id') ?? '';
  const time = request.headers.get('webhook-timestamp') ?? '';
  const signatures = request.headers.get('webhook-signature') ?? '';
  if (!/^[A-Za-z0-9_:.\-]{1,256}$/.test(id) || !/^\d{1,12}$/.test(time) || signatures.length > 2048 || Math.abs(now - Number(time)) > 300) throw new PublicError('invalid_hook_signature', 401);
  if (!secrets.length || secrets.length > 2) throw new PublicError('hook_configuration_unavailable', 503);
  const body = await boundedBody(request, 16384);
  const signed = new TextEncoder().encode(`${id}.${time}.${body}`);
  const candidates = signatures.trim().split(/\s+/).slice(0, 8).filter((s)=>/^v1,[A-Za-z0-9+/]+={0,2}$/.test(s));
  let valid = false;
  for (const secret of secrets){
    let bytes;
    try {
      bytes = new Uint8Array(Uint8Array.from(atob(secret.replace(/^v1,whsec_/, '').replace(/^whsec_/, '')), (c)=>c.charCodeAt(0)));
    } catch  {
      throw new PublicError('hook_configuration_unavailable', 503);
    }
    if (bytes.length < 32) throw new PublicError('hook_configuration_unavailable', 503);
    const key = await crypto.subtle.importKey('raw', bytes, {
      name: 'HMAC',
      hash: 'SHA-256'
    }, false, [
      'verify'
    ]);
    for (const signature of candidates){
      let sig;
      try {
        sig = new Uint8Array(Uint8Array.from(atob(signature.slice(3)), (c)=>c.charCodeAt(0)));
      } catch  {
        continue;
      }
      if (sig.length === 32 && await crypto.subtle.verify('HMAC', key, sig, signed)) valid = true;
    }
  }
  if (!valid) throw new PublicError('invalid_hook_signature', 401);
  try {
    return {
      id,
      body,
      payload: objectValue(JSON.parse(body))
    };
  } catch  {
    throw new PublicError('invalid_hook_payload');
  }
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvc2lnbmVkX3Ntc19ob29rLnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7UHVibGljRXJyb3IsIGJvdW5kZWRCb2R5LCBvYmplY3RWYWx1ZX0gZnJvbSAnLi9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzJztcbi8qKiBTdGFuZGFyZCBXZWJob29rcyB2MSBITUFDLVNIQTI1Ni4gUGVyc2lzdGVudCBpZCByZXBsYXkgY29udHJvbCBpcyBzZXBhcmF0ZS4gKi9cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiB2ZXJpZnlTbXNIb29rKHJlcXVlc3Q6IFJlcXVlc3QsIHNlY3JldHM6IHJlYWRvbmx5IHN0cmluZ1tdLCBub3cgPSBNYXRoLmZsb29yKERhdGUubm93KCkvMTAwMCkpIHtcbiAgY29uc3QgaWQ9cmVxdWVzdC5oZWFkZXJzLmdldCgnd2ViaG9vay1pZCcpID8/ICcnO1xuICBjb25zdCB0aW1lPXJlcXVlc3QuaGVhZGVycy5nZXQoJ3dlYmhvb2stdGltZXN0YW1wJykgPz8gJyc7XG4gIGNvbnN0IHNpZ25hdHVyZXM9cmVxdWVzdC5oZWFkZXJzLmdldCgnd2ViaG9vay1zaWduYXR1cmUnKSA/PyAnJztcbiAgaWYgKCEvXltBLVphLXowLTlfOi5cXC1dezEsMjU2fSQvLnRlc3QoaWQpIHx8ICEvXlxcZHsxLDEyfSQvLnRlc3QodGltZSkgfHwgc2lnbmF0dXJlcy5sZW5ndGg+MjA0OCB8fCBNYXRoLmFicyhub3ctTnVtYmVyKHRpbWUpKT4zMDApIHRocm93IG5ldyBQdWJsaWNFcnJvcignaW52YWxpZF9ob29rX3NpZ25hdHVyZScsNDAxKTtcbiAgaWYgKCFzZWNyZXRzLmxlbmd0aCB8fCBzZWNyZXRzLmxlbmd0aD4yKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoJ2hvb2tfY29uZmlndXJhdGlvbl91bmF2YWlsYWJsZScsNTAzKTtcbiAgY29uc3QgYm9keT1hd2FpdCBib3VuZGVkQm9keShyZXF1ZXN0LDE2Mzg0KTtcbiAgY29uc3Qgc2lnbmVkPW5ldyBUZXh0RW5jb2RlcigpLmVuY29kZShgJHtpZH0uJHt0aW1lfS4ke2JvZHl9YCk7XG4gIGNvbnN0IGNhbmRpZGF0ZXM9c2lnbmF0dXJlcy50cmltKCkuc3BsaXQoL1xccysvKS5zbGljZSgwLDgpLmZpbHRlcihzPT4vXnYxLFtBLVphLXowLTkrL10rPXswLDJ9JC8udGVzdChzKSk7XG4gIGxldCB2YWxpZD1mYWxzZTtcbiAgZm9yIChjb25zdCBzZWNyZXQgb2Ygc2VjcmV0cykge1xuICAgIGxldCBieXRlczogVWludDhBcnJheTxBcnJheUJ1ZmZlcj47XG4gICAgdHJ5IHtieXRlcz1uZXcgVWludDhBcnJheShVaW50OEFycmF5LmZyb20oYXRvYihzZWNyZXQucmVwbGFjZSgvXnYxLHdoc2VjXy8sJycpLnJlcGxhY2UoL153aHNlY18vLCcnKSksYz0+Yy5jaGFyQ29kZUF0KDApKSk7fVxuICAgIGNhdGNoIHt0aHJvdyBuZXcgUHVibGljRXJyb3IoJ2hvb2tfY29uZmlndXJhdGlvbl91bmF2YWlsYWJsZScsNTAzKTt9XG4gICAgaWYgKGJ5dGVzLmxlbmd0aDwzMikgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdob29rX2NvbmZpZ3VyYXRpb25fdW5hdmFpbGFibGUnLDUwMyk7XG4gICAgY29uc3Qga2V5PWF3YWl0IGNyeXB0by5zdWJ0bGUuaW1wb3J0S2V5KCdyYXcnLGJ5dGVzLHtuYW1lOidITUFDJyxoYXNoOidTSEEtMjU2J30sZmFsc2UsWyd2ZXJpZnknXSk7XG4gICAgZm9yIChjb25zdCBzaWduYXR1cmUgb2YgY2FuZGlkYXRlcykge1xuICAgICAgbGV0IHNpZzogVWludDhBcnJheTxBcnJheUJ1ZmZlcj47XG4gICAgICB0cnkge3NpZz1uZXcgVWludDhBcnJheShVaW50OEFycmF5LmZyb20oYXRvYihzaWduYXR1cmUuc2xpY2UoMykpLGM9PmMuY2hhckNvZGVBdCgwKSkpO30gY2F0Y2gge2NvbnRpbnVlO31cbiAgICAgIGlmIChzaWcubGVuZ3RoPT09MzIgJiYgYXdhaXQgY3J5cHRvLnN1YnRsZS52ZXJpZnkoJ0hNQUMnLGtleSxzaWcsc2lnbmVkKSkgdmFsaWQ9dHJ1ZTtcbiAgICB9XG4gIH1cbiAgaWYgKCF2YWxpZCkgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdpbnZhbGlkX2hvb2tfc2lnbmF0dXJlJyw0MDEpO1xuICB0cnkge3JldHVybiB7aWQsYm9keSxwYXlsb2FkOm9iamVjdFZhbHVlKEpTT04ucGFyc2UoYm9keSkpfTt9IGNhdGNoIHt0aHJvdyBuZXcgUHVibGljRXJyb3IoJ2ludmFsaWRfaG9va19wYXlsb2FkJyk7fVxufVxuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQVEsV0FBVyxFQUFFLFdBQVcsRUFBRSxXQUFXLFFBQU8sMkJBQTJCO0FBQy9FLGdGQUFnRixHQUNoRixPQUFPLGVBQWUsY0FBYyxPQUFnQixFQUFFLE9BQTBCLEVBQUUsTUFBTSxLQUFLLEtBQUssQ0FBQyxLQUFLLEdBQUcsS0FBRyxLQUFLO0VBQ2pILE1BQU0sS0FBRyxRQUFRLE9BQU8sQ0FBQyxHQUFHLENBQUMsaUJBQWlCO0VBQzlDLE1BQU0sT0FBSyxRQUFRLE9BQU8sQ0FBQyxHQUFHLENBQUMsd0JBQXdCO0VBQ3ZELE1BQU0sYUFBVyxRQUFRLE9BQU8sQ0FBQyxHQUFHLENBQUMsd0JBQXdCO0VBQzdELElBQUksQ0FBQyw0QkFBNEIsSUFBSSxDQUFDLE9BQU8sQ0FBQyxhQUFhLElBQUksQ0FBQyxTQUFTLFdBQVcsTUFBTSxHQUFDLFFBQVEsS0FBSyxHQUFHLENBQUMsTUFBSSxPQUFPLFNBQU8sS0FBSyxNQUFNLElBQUksWUFBWSwwQkFBeUI7RUFDbEwsSUFBSSxDQUFDLFFBQVEsTUFBTSxJQUFJLFFBQVEsTUFBTSxHQUFDLEdBQUcsTUFBTSxJQUFJLFlBQVksa0NBQWlDO0VBQ2hHLE1BQU0sT0FBSyxNQUFNLFlBQVksU0FBUTtFQUNyQyxNQUFNLFNBQU8sSUFBSSxjQUFjLE1BQU0sQ0FBQyxHQUFHLEdBQUcsQ0FBQyxFQUFFLEtBQUssQ0FBQyxFQUFFLE1BQU07RUFDN0QsTUFBTSxhQUFXLFdBQVcsSUFBSSxHQUFHLEtBQUssQ0FBQyxPQUFPLEtBQUssQ0FBQyxHQUFFLEdBQUcsTUFBTSxDQUFDLENBQUEsSUFBRyw0QkFBNEIsSUFBSSxDQUFDO0VBQ3RHLElBQUksUUFBTTtFQUNWLEtBQUssTUFBTSxVQUFVLFFBQVM7SUFDNUIsSUFBSTtJQUNKLElBQUk7TUFBQyxRQUFNLElBQUksV0FBVyxXQUFXLElBQUksQ0FBQyxLQUFLLE9BQU8sT0FBTyxDQUFDLGNBQWEsSUFBSSxPQUFPLENBQUMsV0FBVSxNQUFLLENBQUEsSUFBRyxFQUFFLFVBQVUsQ0FBQztJQUFLLEVBQzNILE9BQU07TUFBQyxNQUFNLElBQUksWUFBWSxrQ0FBaUM7SUFBSztJQUNuRSxJQUFJLE1BQU0sTUFBTSxHQUFDLElBQUksTUFBTSxJQUFJLFlBQVksa0NBQWlDO0lBQzVFLE1BQU0sTUFBSSxNQUFNLE9BQU8sTUFBTSxDQUFDLFNBQVMsQ0FBQyxPQUFNLE9BQU07TUFBQyxNQUFLO01BQU8sTUFBSztJQUFTLEdBQUUsT0FBTTtNQUFDO0tBQVM7SUFDakcsS0FBSyxNQUFNLGFBQWEsV0FBWTtNQUNsQyxJQUFJO01BQ0osSUFBSTtRQUFDLE1BQUksSUFBSSxXQUFXLFdBQVcsSUFBSSxDQUFDLEtBQUssVUFBVSxLQUFLLENBQUMsS0FBSSxDQUFBLElBQUcsRUFBRSxVQUFVLENBQUM7TUFBSyxFQUFFLE9BQU07UUFBQztNQUFTO01BQ3hHLElBQUksSUFBSSxNQUFNLEtBQUcsTUFBTSxNQUFNLE9BQU8sTUFBTSxDQUFDLE1BQU0sQ0FBQyxRQUFPLEtBQUksS0FBSSxTQUFTLFFBQU07SUFDbEY7RUFDRjtFQUNBLElBQUksQ0FBQyxPQUFPLE1BQU0sSUFBSSxZQUFZLDBCQUF5QjtFQUMzRCxJQUFJO0lBQUMsT0FBTztNQUFDO01BQUc7TUFBSyxTQUFRLFlBQVksS0FBSyxLQUFLLENBQUM7SUFBTTtFQUFFLEVBQUUsT0FBTTtJQUFDLE1BQU0sSUFBSSxZQUFZO0VBQXdCO0FBQ3JIIn0=
// denoCacheMetadata=2735103589987180623,8798029551754699034