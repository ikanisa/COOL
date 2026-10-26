import assert from 'node:assert/strict';
import {generateKeyPairSync, sign, webcrypto} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {renderLocalChallengeDocument} from '../../deploy/platform-supabase-free/local-challenge.mjs';

const FRONT = 'https://platform-admin.collect.ikanisa.com';
const QA = 'https://admin-supabase-qa.collect.ikanisa.com';
const SIBLING = 'https://admin.collect.ikanisa.com';
const PATH = '/admin/auth/local-challenge';
const ATTEMPT = '11111111-1111-4111-8111-111111111111';
const NOW = 1792497600000;
const canonical = value => JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(key => [key, value[key]])));
const json = (value, status = 200) => new Response(JSON.stringify(value), {status, headers: {'Content-Type':'application/json'}});

class Element {
  constructor() { this.listeners = new Map(); this.value = ''; this.textContent = ''; this.disabled = false; this.dataset = {}; this.children = []; this.attributes = {}; this.contentWindow = {}; }
  addEventListener(name, handler) { this.listeners.set(name, handler); }
  removeEventListener(name, handler) { if (this.listeners.get(name) === handler) this.listeners.delete(name); }
  setAttribute(name, value) { this.attributes[name] = value; }
  appendChild(child) { this.children.push(child); child.parent = this; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); }
  focus() { this.focused = true; }
  async emit(name, value = {}) { await this.listeners.get(name)?.(value); }
}
async function harness({origin = FRONT, crypto = webcrypto, response, topLevel = true, render = renderLocalChallengeDocument} = {}) {
  const rendered = await render(new Request(origin + PATH), {origin});
  assert.equal(rendered.status, 200, 'The explicitly configured parent origin must render before its controller is exercised');
  const html = await rendered.text();
  const script = html.match(/<script nonce="[a-f0-9]+">([\s\S]*?)<\/script>/)[1];
  const elements = Object.fromEntries(['pairing-form','pairing','connect','cancel','status','task','challenge'].map(id => [id, new Element()]));
  elements.cancel.disabled = true;
  const document = new Element(); document.visibilityState = 'visible';
  document.getElementById = id => elements[id]; document.createElement = () => new Element();
  const window = new Element(); window.location = {origin, pathname:PATH, search:'', hash:''};
  window.top = topLevel ? window : {}; window.isSecureContext = true;
  const {publicKey, privateKey} = generateKeyPairSync('ed25519');
  const descriptor = {type:'collect.admin.human_challenge.pairing.v1', attempt_id:ATTEMPT,
    operation:'admin.email_otp.send', admin_origin:origin, loopback_port:45123, expires_at_ms:NOW+110_000,
    listener_public_key_ed25519:publicKey.export({format:'der',type:'spki'}).subarray(-32).toString('base64url')};
  const payload = {type:'collect.admin.human_challenge.offer_payload.v1', attempt_id:ATTEMPT,
    operation:descriptor.operation, admin_origin:origin, loopback_port:descriptor.loopback_port,
    nonce:Buffer.alloc(32,7).toString('base64url'), issued_at_ms:NOW, expires_at_ms:descriptor.expires_at_ms};
  const signed = (value = payload, text = canonical(value)) => ({type:'collect.admin.human_challenge.signed_offer.v1',
    payload_base64url:Buffer.from(text).toString('base64url'), signature_ed25519_base64url:sign(null,Buffer.from(text),privateKey).toString('base64url')});
  const calls = [], timers = new Map(); let nextTimer = 1, elapsed = 0;
  const ack = body => ({type:'collect.admin.human_challenge.ack.v1',attempt_id:ATTEMPT,operation:descriptor.operation,
    status:body.token !== undefined ? 'accepted_for_one_cli_operation' : body.error === 'cancelled' ? 'cancelled_without_auth'
      : ['expired','timeout'].includes(body.error) ? 'expired_without_auth' : 'failed_without_auth',session_confirmed:false});
  const fetch = async (url, options) => {
    const call = {url,options,body:options.body ? JSON.parse(options.body) : null}; calls.push(call);
    return response ? response(call, {signed,payload,ack}) : call.body ? json(ack(call.body),202) : json(signed());
  };
  runInNewContext(script, {window,document,crypto,fetch,URL,URLSearchParams,TextDecoder,Uint8Array,AbortController,
    atob,btoa,Date:class extends Date { static now() { return NOW+elapsed; } }, performance:{now:()=>elapsed},
    setTimeout:handler=>{const id=nextTimer++;timers.set(id,handler);return id;},clearTimeout:id=>timers.delete(id)});
  return {window,document,elements,calls,descriptor,payload,signed,timers,html,
    async connect(value = descriptor) { elements.pairing.value = typeof value === 'string' ? value : JSON.stringify(value); await elements['pairing-form'].emit('submit',{preventDefault(){}}); },
    frame() { return elements.challenge.children[0]; },
    async candidate(data = {type:'collect.turnstile.v1',attempt_id:ATTEMPT,token:'SYNTHETIC_ANTIABUSE_ONLY'}, changes = {}) {
      await window.emit('message',{origin,source:this.frame()?.contentWindow,data,...changes});
    },
    async expire() { elapsed=120_001; for (const handler of [...timers.values()]) handler(); },
  };
}

export {FRONT, QA, SIBLING, PATH, ATTEMPT, NOW, canonical, json, harness};
