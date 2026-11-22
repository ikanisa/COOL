import assert from 'node:assert/strict';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';

// Test-only DOM and Cache Storage models. These execute the genuine controller
// and worker source; they do not certify browser rendering or installed PWA use.
export function recoveryDom({running = false, editing = false, loading = false} = {}) {
  let reloads = 0, forbiddenEffects = 0;
  const ids = new Map(), events = new Map();
  const document = {readyState: loading ? 'loading' : 'complete', activeElement: null};
  const element = tag => ({tag, style: {}, attributes: {}, children: [], listeners: {},
    setAttribute(name, value) {this.attributes[name] = value;},
    append(...items) {this.children.push(...items); for (const item of items) if (item.id) ids.set(item.id, item);},
    addEventListener(name, action) {this.listeners[name] = action;},
    focus() {document.activeElement = this;},
  });
  document.body = element('body'); document.activeElement = document.body;
  document.createElement = element;
  document.getElementById = id => ids.get(id) || null;
  document.querySelector = () => running || editing ? {} : null;
  document.addEventListener = (name, action) => events.set(name, action);
  const forbidden = () => {forbiddenEffects++; throw Error('Forbidden recovery effect');};
  const window = {location: {reload() {reloads++;}},
    localStorage: new Proxy({}, {get: forbidden}), sessionStorage: new Proxy({}, {get: forbidden}),
    indexedDB: new Proxy({}, {get: forbidden})};
  const context = vm.createContext({document, window, fetch: forbidden,
    navigator: {serviceWorker: new Proxy({}, {get: forbidden})}, URL,
    setTimeout: forbidden, setInterval: forbidden});
  return {context, document, events, get reloads() {return reloads;},
    get forbiddenEffects() {return forbiddenEffects;},
    run(source) {vm.runInContext(source, context, {timeout: 1000});},
    panel() {return document.getElementById('collect-static-recovery');}};
}

export async function installedWorker(source, origin, files) {
  const cacheStores = new Map(), handlers = new Map();
  let fetches = 0;
  const urlOf = value => new URL(typeof value === 'string' ? value : value.url, origin).href;
  const copy = response => {
    const result = Response.prototype.clone.call(response);
    Object.defineProperties(result, {url: {value: response.url}, type: {value: response.type}});
    return result;
  };
  const cacheFor = key => {
    if (!cacheStores.has(key)) cacheStores.set(key, new Map());
    const values = cacheStores.get(key);
    return {async keys() {return [...values.keys()].map(url => new Request(url));},
      async match(value) {const response = values.get(urlOf(value)); return response && copy(response);},
      async put(request, response) {values.set(urlOf(request), copy(response));},
      async delete(value) {return values.delete(urlOf(value));}};
  };
  const caches = {async keys() {return [...cacheStores.keys()];},
    async open(key) {return cacheFor(key);}, async delete(key) {return cacheStores.delete(key);}};
  const self = {location: {href: origin + '/custom-sw.js', origin},
    addEventListener(name, handler) {handlers.set(name, handler);},
    skipWaiting() {throw Error('No forced activation');},
    clients: {claim() {throw Error('No forced client takeover');}}};
  // Browser WorkerGlobalScope supplies its script URL as Request's API base.
  // Node's standalone constructor has no such base; preserve Request inputs and
  // normal constructor options while resolving relative URL inputs here only.
  class WorkerRequest extends Request {
    constructor(input, init) {
      super(input instanceof Request ? input : new URL(input, self.location.href), init);
    }
  }
  const context = vm.createContext({self, caches, URL, Request: WorkerRequest, Response,
    crypto: webcrypto, Uint8Array, Promise,
    fetch: async request => {
      fetches++;
      assert.equal(request.credentials, 'omit'); assert.equal(request.redirect, 'error');
      const url = urlOf(request), bytes = files.get(url);
      assert.ok(bytes, 'Every admitted static URL must have real fixture bytes: ' + url);
      const response = new Response(bytes);
      Object.defineProperties(response, {url: {value: url}, type: {value: 'basic'}});
      return response;
    }});
  vm.runInContext(source, context, {timeout: 1000});
  const inventory = vm.runInContext('({name:CACHE_NAME, urls:CACHE_URLS, hashes:CACHE_HASHES})', context);
  let installation;
  handlers.get('install')({waitUntil(value) {installation = value;}});
  await installation;
  // Verify the complete fixture inventory using the unmodified production
  // worker's own admission function, not just a cache-name marker.
  assert.equal(await vm.runInContext('hasAdmittedBuildCache()', context), true);
  const installFetches = fetches;
  return {inventory, installFetches, get fetches() {return fetches;},
    async read(url) {let result; handlers.get('fetch')({request: new Request(url),
      respondWith(value) {result = value;}}); assert.ok(result); return await result;},
    async evict(url) {await cacheFor(inventory.name).delete(url);},
    async admitted() {return await vm.runInContext('hasAdmittedBuildCache()', context);}};
}
