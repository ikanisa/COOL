/** Boundary errors contain developer-authored codes, never user or provider values. */ export class PublicError extends Error {
  code;
  status;
  constructor(code, status = 400){
    super(code), this.code = code, this.status = status;
    this.name = 'PublicError';
  }
}
export const RECEIPT_CONTRACT_VERSION = 2;
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const SHA256 = /^[a-f0-9]{64}$/;
const encoder = new TextEncoder();
export function objectValue(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new PublicError('invalid_payload');
  return value;
}
export function boundedText(value, code, maximum, trim = true) {
  if (typeof value !== 'string' || !value.trim() || encoder.encode(value).length > maximum) throw new PublicError(code);
  return trim ? value.trim() : value;
}
export function uuid(value, code) {
  if (typeof value !== 'string' || !UUID.test(value)) throw new PublicError(code);
  return value.toLowerCase();
}
export async function boundedBody(message, maximum) {
  if (!Number.isSafeInteger(maximum) || maximum < 1) throw new Error('Invalid configured bound');
  const length = message.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maximum)) throw new PublicError('payload_too_large', 413);
  if (!message.body) return '';
  const reader = message.body.getReader();
  const parts = [];
  let count = 0;
  try {
    for(;;){
      const next = await reader.read();
      if (next.done) break;
      count += next.value.byteLength;
      if (count > maximum) {
        await reader.cancel();
        throw new PublicError('payload_too_large', 413);
      }
      parts.push(next.value);
    }
  } finally{
    reader.releaseLock();
  }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const part of parts){
    bytes.set(part, offset);
    offset += part.length;
  }
  try {
    return new TextDecoder('utf-8', {
      fatal: true
    }).decode(bytes);
  } catch  {
    throw new PublicError('invalid_utf8');
  }
}
export async function boundedJson(request, maximum = 16_384) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') ?? '')) throw new PublicError('json_required', 415);
  try {
    return objectValue(JSON.parse(await boundedBody(request, maximum)));
  } catch (error) {
    if (error instanceof PublicError) throw error;
    throw new PublicError('invalid_json');
  }
}
export function publicFailure(error) {
  if (error instanceof PublicError) return {
    error: error.code,
    status: error.status
  };
  const message = error instanceof Error ? error.message : '';
  if ([
    'Authentication required',
    'Internal function authorization failed',
    'Unauthorized'
  ].includes(message)) return {
    error: 'authentication_required',
    status: 401
  };
  return {
    error: 'service_unavailable',
    status: 503
  };
}
export async function fetchJson(url, init, milliseconds = 8_000, maxBytes = 65_536) {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(milliseconds),
    redirect: 'error'
  });
  const raw = await boundedBody(response, maxBytes);
  let data = null;
  if (raw) {
    try {
      data = JSON.parse(raw);
    } catch  {
      throw new PublicError('invalid_provider_response', 502);
    }
  }
  return {
    ok: response.ok,
    status: response.status,
    data
  };
}
export function requireReceiptContract(value) {
  if (value !== RECEIPT_CONTRACT_VERSION) throw new PublicError('receipt_contract_unavailable', 503);
}
export function validateReceiptAck(value, owner, envelope, bodyHash) {
  const r = objectValue(value);
  if (r.contract_version !== 2 || r.stored !== true || typeof r.raw_sms_id !== 'string' || !UUID.test(r.raw_sms_id) || r.owner_user_id !== owner || r.client_envelope_id !== envelope || r.body_sha256 !== bodyHash || !SHA256.test(bodyHash)) throw new PublicError('durable_receipt_not_verified', 503);
  return {
    contract_version: 2,
    stored: true,
    raw_sms_id: r.raw_sms_id.toLowerCase(),
    client_envelope_id: envelope,
    owner_user_id: owner,
    body_sha256: bodyHash
  };
}
export function zonedInstant(value) {
  if (value === null || value === undefined) return null;
  const s = boundedText(value, 'invalid_receipt_time', 40);
  if (!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(s) || !Number.isFinite(Date.parse(s))) throw new PublicError('invalid_receipt_time');
  const parts = s.slice(0, 19).split(/[-T :]/).map(Number);
  const [y, m, d, h, min, sec] = parts;
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  if (y < 100 || m < 1 || m > 12 || d < 1 || d > days || h > 23 || min > 59 || sec > 59) throw new PublicError('invalid_receipt_time');
  return s;
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcHJvZHVjdGlvbl9jb250cmFjdC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyIvKiogQm91bmRhcnkgZXJyb3JzIGNvbnRhaW4gZGV2ZWxvcGVyLWF1dGhvcmVkIGNvZGVzLCBuZXZlciB1c2VyIG9yIHByb3ZpZGVyIHZhbHVlcy4gKi9cbmV4cG9ydCBjbGFzcyBQdWJsaWNFcnJvciBleHRlbmRzIEVycm9yIHtcbiAgY29uc3RydWN0b3IocmVhZG9ubHkgY29kZTogc3RyaW5nLCByZWFkb25seSBzdGF0dXMgPSA0MDApIHsgc3VwZXIoY29kZSk7IHRoaXMubmFtZSA9ICdQdWJsaWNFcnJvcic7IH1cbn1cbmV4cG9ydCBjb25zdCBSRUNFSVBUX0NPTlRSQUNUX1ZFUlNJT04gPSAyO1xuZXhwb3J0IGNvbnN0IFVVSUQgPSAvXlswLTlhLWZdezh9LVswLTlhLWZdezR9LVsxLTVdWzAtOWEtZl17M30tWzg5YWJdWzAtOWEtZl17M30tWzAtOWEtZl17MTJ9JC9pO1xuZXhwb3J0IGNvbnN0IFNIQTI1NiA9IC9eW2EtZjAtOV17NjR9JC87XG5jb25zdCBlbmNvZGVyID0gbmV3IFRleHRFbmNvZGVyKCk7XG5leHBvcnQgZnVuY3Rpb24gb2JqZWN0VmFsdWUodmFsdWU6IHVua25vd24pOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB7XG4gIGlmICh2YWx1ZSA9PT0gbnVsbCB8fCB0eXBlb2YgdmFsdWUgIT09ICdvYmplY3QnIHx8IEFycmF5LmlzQXJyYXkodmFsdWUpKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoJ2ludmFsaWRfcGF5bG9hZCcpO1xuICByZXR1cm4gdmFsdWUgYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj47XG59XG5leHBvcnQgZnVuY3Rpb24gYm91bmRlZFRleHQodmFsdWU6IHVua25vd24sIGNvZGU6IHN0cmluZywgbWF4aW11bTogbnVtYmVyLCB0cmltID0gdHJ1ZSk6IHN0cmluZyB7XG4gIGlmICh0eXBlb2YgdmFsdWUgIT09ICdzdHJpbmcnIHx8ICF2YWx1ZS50cmltKCkgfHwgZW5jb2Rlci5lbmNvZGUodmFsdWUpLmxlbmd0aCA+IG1heGltdW0pIHRocm93IG5ldyBQdWJsaWNFcnJvcihjb2RlKTtcbiAgcmV0dXJuIHRyaW0gPyB2YWx1ZS50cmltKCkgOiB2YWx1ZTtcbn1cbmV4cG9ydCBmdW5jdGlvbiB1dWlkKHZhbHVlOiB1bmtub3duLCBjb2RlOiBzdHJpbmcpOiBzdHJpbmcge1xuICBpZiAodHlwZW9mIHZhbHVlICE9PSAnc3RyaW5nJyB8fCAhVVVJRC50ZXN0KHZhbHVlKSkgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKGNvZGUpO1xuICByZXR1cm4gdmFsdWUudG9Mb3dlckNhc2UoKTtcbn1cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBib3VuZGVkQm9keShtZXNzYWdlOiBSZXF1ZXN0IHwgUmVzcG9uc2UsIG1heGltdW06IG51bWJlcik6IFByb21pc2U8c3RyaW5nPiB7XG4gIGlmICghTnVtYmVyLmlzU2FmZUludGVnZXIobWF4aW11bSkgfHwgbWF4aW11bSA8IDEpIHRocm93IG5ldyBFcnJvcignSW52YWxpZCBjb25maWd1cmVkIGJvdW5kJyk7XG4gIGNvbnN0IGxlbmd0aCA9IG1lc3NhZ2UuaGVhZGVycy5nZXQoJ2NvbnRlbnQtbGVuZ3RoJyk7XG4gIGlmIChsZW5ndGggIT09IG51bGwgJiYgKCEvXlxcZCskLy50ZXN0KGxlbmd0aCkgfHwgTnVtYmVyKGxlbmd0aCkgPiBtYXhpbXVtKSkgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdwYXlsb2FkX3Rvb19sYXJnZScsIDQxMyk7XG4gIGlmICghbWVzc2FnZS5ib2R5KSByZXR1cm4gJyc7XG4gIGNvbnN0IHJlYWRlciA9IG1lc3NhZ2UuYm9keS5nZXRSZWFkZXIoKTsgY29uc3QgcGFydHM6IFVpbnQ4QXJyYXlbXSA9IFtdOyBsZXQgY291bnQgPSAwO1xuICB0cnkge1xuICAgIGZvciAoOzspIHtcbiAgICAgIGNvbnN0IG5leHQgPSBhd2FpdCByZWFkZXIucmVhZCgpOyBpZiAobmV4dC5kb25lKSBicmVhaztcbiAgICAgIGNvdW50ICs9IG5leHQudmFsdWUuYnl0ZUxlbmd0aDtcbiAgICAgIGlmIChjb3VudCA+IG1heGltdW0pIHsgYXdhaXQgcmVhZGVyLmNhbmNlbCgpOyB0aHJvdyBuZXcgUHVibGljRXJyb3IoJ3BheWxvYWRfdG9vX2xhcmdlJywgNDEzKTsgfVxuICAgICAgcGFydHMucHVzaChuZXh0LnZhbHVlKTtcbiAgICB9XG4gIH0gZmluYWxseSB7IHJlYWRlci5yZWxlYXNlTG9jaygpOyB9XG4gIGNvbnN0IGJ5dGVzID0gbmV3IFVpbnQ4QXJyYXkoY291bnQpOyBsZXQgb2Zmc2V0ID0gMDtcbiAgZm9yIChjb25zdCBwYXJ0IG9mIHBhcnRzKSB7IGJ5dGVzLnNldChwYXJ0LCBvZmZzZXQpOyBvZmZzZXQgKz0gcGFydC5sZW5ndGg7IH1cbiAgdHJ5IHsgcmV0dXJuIG5ldyBUZXh0RGVjb2RlcigndXRmLTgnLCB7ZmF0YWw6IHRydWV9KS5kZWNvZGUoYnl0ZXMpOyB9XG4gIGNhdGNoIHsgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdpbnZhbGlkX3V0ZjgnKTsgfVxufVxuZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIGJvdW5kZWRKc29uKHJlcXVlc3Q6IFJlcXVlc3QsIG1heGltdW0gPSAxNl8zODQpOiBQcm9taXNlPFJlY29yZDxzdHJpbmcsIHVua25vd24+PiB7XG4gIGlmICghL15hcHBsaWNhdGlvblxcL2pzb24oPzpcXHMqO3wkKS9pLnRlc3QocmVxdWVzdC5oZWFkZXJzLmdldCgnY29udGVudC10eXBlJykgPz8gJycpKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoJ2pzb25fcmVxdWlyZWQnLCA0MTUpO1xuICB0cnkgeyByZXR1cm4gb2JqZWN0VmFsdWUoSlNPTi5wYXJzZShhd2FpdCBib3VuZGVkQm9keShyZXF1ZXN0LCBtYXhpbXVtKSkpOyB9XG4gIGNhdGNoIChlcnJvcikgeyBpZiAoZXJyb3IgaW5zdGFuY2VvZiBQdWJsaWNFcnJvcikgdGhyb3cgZXJyb3I7IHRocm93IG5ldyBQdWJsaWNFcnJvcignaW52YWxpZF9qc29uJyk7IH1cbn1cbmV4cG9ydCBmdW5jdGlvbiBwdWJsaWNGYWlsdXJlKGVycm9yOiB1bmtub3duKToge2Vycm9yOiBzdHJpbmc7IHN0YXR1czogbnVtYmVyfSB7XG4gIGlmIChlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yKSByZXR1cm4ge2Vycm9yOiBlcnJvci5jb2RlLCBzdGF0dXM6IGVycm9yLnN0YXR1c307XG4gIGNvbnN0IG1lc3NhZ2UgPSBlcnJvciBpbnN0YW5jZW9mIEVycm9yID8gZXJyb3IubWVzc2FnZSA6ICcnO1xuICBpZiAoWydBdXRoZW50aWNhdGlvbiByZXF1aXJlZCcsJ0ludGVybmFsIGZ1bmN0aW9uIGF1dGhvcml6YXRpb24gZmFpbGVkJywnVW5hdXRob3JpemVkJ10uaW5jbHVkZXMobWVzc2FnZSkpIHJldHVybiB7ZXJyb3I6J2F1dGhlbnRpY2F0aW9uX3JlcXVpcmVkJyxzdGF0dXM6NDAxfTtcbiAgcmV0dXJuIHtlcnJvcjonc2VydmljZV91bmF2YWlsYWJsZScsc3RhdHVzOjUwM307XG59XG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gZmV0Y2hKc29uKHVybDogc3RyaW5nLCBpbml0OiBSZXF1ZXN0SW5pdCwgbWlsbGlzZWNvbmRzID0gOF8wMDAsIG1heEJ5dGVzID0gNjVfNTM2KTogUHJvbWlzZTx7b2s6IGJvb2xlYW47IHN0YXR1czogbnVtYmVyOyBkYXRhOiB1bmtub3dufT4ge1xuICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGZldGNoKHVybCwgey4uLmluaXQsIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dChtaWxsaXNlY29uZHMpLCByZWRpcmVjdDonZXJyb3InfSk7XG4gIGNvbnN0IHJhdyA9IGF3YWl0IGJvdW5kZWRCb2R5KHJlc3BvbnNlLCBtYXhCeXRlcyk7XG4gIGxldCBkYXRhOiB1bmtub3duID0gbnVsbDtcbiAgaWYgKHJhdykgeyB0cnkgeyBkYXRhID0gSlNPTi5wYXJzZShyYXcpOyB9IGNhdGNoIHsgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdpbnZhbGlkX3Byb3ZpZGVyX3Jlc3BvbnNlJyw1MDIpOyB9IH1cbiAgcmV0dXJuIHtvazpyZXNwb25zZS5vayxzdGF0dXM6cmVzcG9uc2Uuc3RhdHVzLGRhdGF9O1xufVxuZXhwb3J0IGZ1bmN0aW9uIHJlcXVpcmVSZWNlaXB0Q29udHJhY3QodmFsdWU6IHVua25vd24pOiB2b2lkIHtcbiAgaWYgKHZhbHVlICE9PSBSRUNFSVBUX0NPTlRSQUNUX1ZFUlNJT04pIHRocm93IG5ldyBQdWJsaWNFcnJvcigncmVjZWlwdF9jb250cmFjdF91bmF2YWlsYWJsZScsNTAzKTtcbn1cbmV4cG9ydCB0eXBlIFJlY2VpcHRBY2sgPSB7Y29udHJhY3RfdmVyc2lvbjoyO3N0b3JlZDp0cnVlO3Jhd19zbXNfaWQ6c3RyaW5nO2NsaWVudF9lbnZlbG9wZV9pZDpzdHJpbmc7b3duZXJfdXNlcl9pZDpzdHJpbmc7Ym9keV9zaGEyNTY6c3RyaW5nfTtcbmV4cG9ydCBmdW5jdGlvbiB2YWxpZGF0ZVJlY2VpcHRBY2sodmFsdWU6IHVua25vd24sIG93bmVyOiBzdHJpbmcsIGVudmVsb3BlOiBzdHJpbmcsIGJvZHlIYXNoOiBzdHJpbmcpOiBSZWNlaXB0QWNrIHtcbiAgY29uc3QgciA9IG9iamVjdFZhbHVlKHZhbHVlKTtcbiAgaWYgKHIuY29udHJhY3RfdmVyc2lvbiAhPT0gMiB8fCByLnN0b3JlZCAhPT0gdHJ1ZSB8fCB0eXBlb2Ygci5yYXdfc21zX2lkICE9PSAnc3RyaW5nJyB8fCAhVVVJRC50ZXN0KHIucmF3X3Ntc19pZCkgfHxcbiAgICAgIHIub3duZXJfdXNlcl9pZCAhPT0gb3duZXIgfHwgci5jbGllbnRfZW52ZWxvcGVfaWQgIT09IGVudmVsb3BlIHx8IHIuYm9keV9zaGEyNTYgIT09IGJvZHlIYXNoIHx8ICFTSEEyNTYudGVzdChib2R5SGFzaCkpIHRocm93IG5ldyBQdWJsaWNFcnJvcignZHVyYWJsZV9yZWNlaXB0X25vdF92ZXJpZmllZCcsNTAzKTtcbiAgcmV0dXJuIHtjb250cmFjdF92ZXJzaW9uOjIsc3RvcmVkOnRydWUscmF3X3Ntc19pZDpyLnJhd19zbXNfaWQudG9Mb3dlckNhc2UoKSxjbGllbnRfZW52ZWxvcGVfaWQ6ZW52ZWxvcGUsb3duZXJfdXNlcl9pZDpvd25lcixib2R5X3NoYTI1Njpib2R5SGFzaH07XG59XG5leHBvcnQgZnVuY3Rpb24gem9uZWRJbnN0YW50KHZhbHVlOiB1bmtub3duKTogc3RyaW5nIHwgbnVsbCB7XG4gIGlmICh2YWx1ZSA9PT0gbnVsbCB8fCB2YWx1ZSA9PT0gdW5kZWZpbmVkKSByZXR1cm4gbnVsbDtcbiAgY29uc3QgcyA9IGJvdW5kZWRUZXh0KHZhbHVlLCdpbnZhbGlkX3JlY2VpcHRfdGltZScsNDApO1xuICBpZiAoIS9eXFxkezR9LVxcZHsyfS1cXGR7Mn1bVCBdXFxkezJ9OlxcZHsyfTpcXGR7Mn0oPzpcXC5cXGR7MSw2fSk/KD86WnxbKy1dXFxkezJ9OlxcZHsyfSkkLy50ZXN0KHMpIHx8ICFOdW1iZXIuaXNGaW5pdGUoRGF0ZS5wYXJzZShzKSkpIHRocm93IG5ldyBQdWJsaWNFcnJvcignaW52YWxpZF9yZWNlaXB0X3RpbWUnKTtcbiAgY29uc3QgcGFydHM9cy5zbGljZSgwLDE5KS5zcGxpdCgvWy1UIDpdLykubWFwKE51bWJlcik7XG4gIGNvbnN0IFt5LG0sZCxoLG1pbixzZWNdPXBhcnRzO1xuICBjb25zdCBkYXlzID0gbmV3IERhdGUoRGF0ZS5VVEMoeSxtLDApKS5nZXRVVENEYXRlKCk7XG4gIGlmICh5PDEwMCB8fCBtPDEgfHwgbT4xMiB8fCBkPDEgfHwgZD5kYXlzIHx8IGg+MjMgfHwgbWluPjU5IHx8IHNlYz41OSkgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKCdpbnZhbGlkX3JlY2VpcHRfdGltZScpO1xuICByZXR1cm4gcztcbn1cbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxxRkFBcUYsR0FDckYsT0FBTyxNQUFNLG9CQUFvQjs7O0VBQy9CLFlBQVksQUFBUyxJQUFZLEVBQUUsQUFBUyxTQUFTLEdBQUcsQ0FBRTtJQUFFLEtBQUssQ0FBQyxZQUE3QyxPQUFBLFdBQXVCLFNBQUE7SUFBNkIsSUFBSSxDQUFDLElBQUksR0FBRztFQUFlO0FBQ3RHO0FBQ0EsT0FBTyxNQUFNLDJCQUEyQixFQUFFO0FBQzFDLE9BQU8sTUFBTSxPQUFPLDZFQUE2RTtBQUNqRyxPQUFPLE1BQU0sU0FBUyxpQkFBaUI7QUFDdkMsTUFBTSxVQUFVLElBQUk7QUFDcEIsT0FBTyxTQUFTLFlBQVksS0FBYztFQUN4QyxJQUFJLFVBQVUsUUFBUSxPQUFPLFVBQVUsWUFBWSxNQUFNLE9BQU8sQ0FBQyxRQUFRLE1BQU0sSUFBSSxZQUFZO0VBQy9GLE9BQU87QUFDVDtBQUNBLE9BQU8sU0FBUyxZQUFZLEtBQWMsRUFBRSxJQUFZLEVBQUUsT0FBZSxFQUFFLE9BQU8sSUFBSTtFQUNwRixJQUFJLE9BQU8sVUFBVSxZQUFZLENBQUMsTUFBTSxJQUFJLE1BQU0sUUFBUSxNQUFNLENBQUMsT0FBTyxNQUFNLEdBQUcsU0FBUyxNQUFNLElBQUksWUFBWTtFQUNoSCxPQUFPLE9BQU8sTUFBTSxJQUFJLEtBQUs7QUFDL0I7QUFDQSxPQUFPLFNBQVMsS0FBSyxLQUFjLEVBQUUsSUFBWTtFQUMvQyxJQUFJLE9BQU8sVUFBVSxZQUFZLENBQUMsS0FBSyxJQUFJLENBQUMsUUFBUSxNQUFNLElBQUksWUFBWTtFQUMxRSxPQUFPLE1BQU0sV0FBVztBQUMxQjtBQUNBLE9BQU8sZUFBZSxZQUFZLE9BQTJCLEVBQUUsT0FBZTtFQUM1RSxJQUFJLENBQUMsT0FBTyxhQUFhLENBQUMsWUFBWSxVQUFVLEdBQUcsTUFBTSxJQUFJLE1BQU07RUFDbkUs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
// denoCacheMetadata=2639049386958612393,7782160329262575473