import {StorageProtocolError, validKey} from './protocol.js';
const enc = new TextEncoder();
const error = code => new StorageProtocolError(code, {retryable: true});
async function boundedBytes(response, maximum) {
  const length = response.headers.get('Content-Length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maximum)) throw error('storage_response_too_large');
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader(), chunks = []; let size = 0;
  try { while (true) { const {done, value} = await reader.read(); if (done) break; size += value.length;
    if (size > maximum) { await reader.cancel(); throw error('storage_response_too_large'); } chunks.push(value); }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size); let offset = 0; for (const c of chunks) { result.set(c, offset); offset += c.length; } return result;
}
async function boundedJson(response, {maximum = 1_000_000, exactLength = false} = {}) {
  try {
    const bytes = await boundedBytes(response, maximum), length = response.headers.get('Content-Length');
    if (exactLength && length !== null && Number(length) !== bytes.length) throw error('storage_response_invalid');
    return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  }
  catch { throw error('storage_response_invalid'); }
}
function isMissingObject(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      body.code !== undefined && body.code !== 'NoSuchKey' ||
      body.statusCode !== undefined && body.statusCode !== '404' && body.statusCode !== 404 ||
      body.status !== undefined && body.status !== '404' && body.status !== 404 ||
      body.error !== undefined && !['NoSuchKey', 'not_found', 'Not Found', 'Object not found'].includes(body.error) ||
      body.message !== undefined && (typeof body.message !== 'string' || !/^(?:object not found|the resource was not found|the specified key does not exist\.)$/i.test(body.message))) return false;
  return body.code === 'NoSuchKey' || body.error === 'NoSuchKey' ||
    (String(body.statusCode ?? body.status ?? '') === '404' && /^(?:object not found|the resource was not found)$/i.test(body.message ?? ''));
}
function isLegacyMissingObject(body) {
  // Supabase's legacy error renderer can return HTTP 400 while preserving its
  // typed Storage 404 in this exact JSON envelope. Generic 400 is never absence.
  return body && typeof body === 'object' && !Array.isArray(body) &&
    Object.keys(body).sort().join(',') === 'code,error,message,statusCode' &&
    body.statusCode === '404' && body.error === 'not_found' &&
    body.message === 'Object not found' && body.code === 'NoSuchKey';
}
export class SupabaseNativeTransport {
  constructor({url, secretKey, bucket = 'collect-evidence', fetchImpl = fetch, timeoutMs = 30_000, allowInsecureLoopback = false, pageSize = 1000, maxObjects = 100_000, maxDepth = 32, maxPages = 10_000, maxEntries = 200_000, maxPrefixes = 10_000, authorizeMutation = null}) {
    const u = new URL(url); const local = ['localhost', '127.0.0.1', '[::1]', '::1'].includes(u.hostname);
    if (u.username || u.password || u.search || u.hash || u.pathname !== '/' || (u.protocol !== 'https:' && !(allowInsecureLoopback && local && u.protocol === 'http:'))) throw new TypeError('Verified HTTPS Storage origin required');
    if (typeof secretKey !== 'string' || secretKey.length < 8 || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$/.test(bucket)) throw new TypeError('Invalid server Storage configuration');
    if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 1000 || !Number.isInteger(maxObjects) || maxObjects < 1 || !Number.isInteger(maxDepth) || maxDepth < 1 || [maxPages,maxEntries,maxPrefixes].some(x=>!Number.isInteger(x)||x<1)) throw new TypeError('Invalid inventory limits');
    this.authorizeMutation=authorizeMutation;this.url = u.origin; this.secretKey = secretKey; this.bucket = bucket; this.fetchImpl = fetchImpl; this.timeoutMs = timeoutMs; this.pageSize = pageSize; this.maxObjects = maxObjects; this.maxDepth = maxDepth; this.maxPages=maxPages; this.maxEntries=maxEntries; this.maxPrefixes=maxPrefixes;
  }
  path(key) { return validKey(key).split('/').map(encodeURIComponent).join('/'); }
  async request(path, {method = 'GET', body, headers = {}} = {}) {
    return this.fetchImpl(this.url + '/storage/v1' + path, {method, body, redirect: 'error', signal: AbortSignal.timeout(this.timeoutMs), headers: {apikey: this.secretKey, ...(this.secretKey.startsWith('sb_secret_') ? {} : {Authorization: 'Bearer ' + this.secretKey}), ...headers}});
  }
  async uploadImmutable(key, bytes, httpMetadata = {}) {
    if(typeof this.authorizeMutation!=='function')throw error('storage_application_admission_required');await this.authorizeMutation();
    if(!await this.bucketVerified())throw error('storage_private_bucket_required');
    const response = await this.request('/object/' + this.bucket + '/' + this.path(key), {method: 'POST', body: bytes, headers: {'Content-Type': httpMetadata.contentType ?? 'application/octet-stream', 'Cache-Control': 'no-store', 'x-upsert': 'false'}});
    // 404 deliberately remains an error status, never a null-success sentinel.
    await response.body?.cancel(); return {status: response.status};
  }
  async bucketVerified() {
    const r = await this.request('/bucket/' + this.bucket);
    if (r.status !== 200) { await r.body?.cancel(); return false; }
    const b = await boundedJson(r); return b?.id === this.bucket && b?.name === this.bucket && b?.public === false;
  }
  async probe(key, {maxBytes = 8_000_000} = {}) {
    if(!await this.bucketVerified())return {headStatus:0,getStatus:0,absent:false,bucketVerified:false};
    const path = '/object/authenticated/' + this.bucket + '/' + this.path(key);
    const head = await this.request(path, {method: 'HEAD'}); const get = await this.request(path);
    if (head.status === 200 && get.status === 200) {
      const bytes = await boundedBytes(get, maxBytes), length = head.headers.get('Content-Length');
      if (length !== null && (!/^\d+$/.test(length) || Number(length) !== bytes.length)) throw error('storage_head_get_mismatch');
      return {headStatus: 200, getStatus: 200, bytes, etag: get.headers.get('ETag') ?? head.headers.get('ETag'), absent: false, bucketVerified: true};
    }
    if (head.status === 404 && get.status === 404) {
      const body = await boundedJson(get), verified = isMissingObject(body) && await this.bucketVerified();
      return {headStatus: 404, getStatus: 404, absent: verified, bucketVerified: verified};
    }
    if (head.status === 400 && get.status === 400 &&
        get.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() === 'application/json') {
      const body = await boundedJson(get, {maximum: 4096, exactLength: true}), verified = isLegacyMissingObject(body) && await this.bucketVerified();
      if (verified) return {
        // Existing protocol/journal fields describe effective Storage status.
        // Preserve the actual HTTP statuses and the exact normalization basis.
        headStatus: 404, getStatus: 404, absent: true, bucketVerified: true,
        httpHeadStatus: 400, httpGetStatus: 400,
        storageStatusCode: '404', storageErrorCode: 'NoSuchKey',
        absenceStatusBasis: 'supabase_legacy_nosuchkey_v1',
      };
    }
    await get.body?.cancel(); return {headStatus: head.status, getStatus: get.status, absent: false, bucketVerified: false};
  }
  async remove(key) {
    if(typeof this.authorizeMutation!=='function')throw error('storage_application_admission_required');await this.authorizeMutation();
    if(!await this.bucketVerified())throw error('storage_private_bucket_required');
    const response = await this.request('/object/' + this.bucket, {method: 'DELETE', body: JSON.stringify({prefixes: [validKey(key)]}), headers: {'Content-Type': 'application/json'}});
    await response.body?.cancel(); return {status: response.status};
  }
  async listAll() {
    if (!await this.bucketVerified()) throw error('storage_bucket_unverified');
    const queue = [{prefix: '', depth: 0}], visited = new Set(), seen = new Set(), objects = [];let pages=0,entries=0;const queued=new Set(['']);
    while (queue.length) {
      const {prefix, depth} = queue.shift(); if (visited.has(prefix)) throw error('storage_inventory_cycle'); visited.add(prefix);
      let offset = 0;const prefixEntries=new Set();
      while (true) {
        if(++pages>this.maxPages)throw error('storage_inventory_page_budget');
        const r = await this.request('/object/list/' + this.bucket, {method: 'POST', body: JSON.stringify({prefix, limit: this.pageSize, offset, sortBy: {column: 'name', order: 'asc'}}), headers: {'Content-Type': 'application/json'}});
        if (r.status !== 200) { await r.body?.cancel(); throw error('storage_inventory_failed'); }
        const page = await boundedJson(r); if (!Array.isArray(page) || page.length > this.pageSize) throw error('storage_inventory_invalid');
        for (const item of page) {
          if (!item || typeof item.name !== 'string' || !item.name || item.name.includes('/') || item.name === '.' || item.name === '..') throw error('storage_inventory_invalid');
          const key = prefix + item.name;if(++entries>this.maxEntries)throw error('storage_inventory_entry_budget');if(prefixEntries.has(item.name))throw error('storage_inventory_changed');prefixEntries.add(item.name);
          if (item.id === null && item.metadata === null) {
            if (depth + 1 > this.maxDepth) throw error('storage_inventory_depth_exceeded');
            const next=key+'/';if(queued.has(next))throw error('storage_inventory_cycle');if(queued.size>=this.maxPrefixes)throw error('storage_inventory_prefix_budget');queued.add(next);queue.push({prefix: next, depth: depth + 1});
          } else {
            validKey(key); if (typeof item.id !== 'string' || !item.id || seen.has(key)) throw error('storage_inventory_changed'); seen.add(key);
            const size = item.metadata?.size; if (size !== undefined && (!Number.isSafeInteger(size) || size < 0)) throw error('storage_inventory_invalid');
            objects.push({key, remoteId: item.id, size: size ?? null, etag: item.metadata?.eTag ?? null});
            if (objects.length > this.maxObjects) throw error('storage_inventory_limit_exceeded');
          }
        }
        offset += page.length;
        if (page.length < this.pageSize) break;
      }
    }
    // Listing is complete traversal, NOT an atomic snapshot. Destructive use
    // additionally requires the trusted writer/retention fence in the contract.
    return {complete: true, atomicSnapshot: false, objects};
  }
}
