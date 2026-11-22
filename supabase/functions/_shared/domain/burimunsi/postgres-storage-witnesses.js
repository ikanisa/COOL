import {requirePort,requireThat} from './errors.js';
import {requireId,canonicalJson} from './values.js';

const check=value=>requireThat(value,'storage_preflight_unavailable',503);
const copy=value=>JSON.parse(canonicalJson(value));
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');

/** Reservation bytes are intentionally scrubbed by the application-commit
 * trigger. Clearing them is not an object-identity change. Every other selected
 * journal field, including the committed state and deletion/upload barriers,
 * remains part of the proof. No caller obtains replacement reservation bytes. */
export function immutableStorageJournal(journal){
  const saved=copy(journal);
  delete saved.reservation.sealed_body;
  delete saved.reservation.cleared_at;
  return saved;
}

/** Request/application-admission scoped, encrypted-byte preflight. Plans and
 * witnesses are module-private capabilities: JSON, a digest, a provider ACK or
 * caller-supplied plaintext cannot construct one. Call prefetch ONLY after the
 * staging SQL transaction has returned. Transactional consumers may only call
 * sealed(), which performs local checks and never invokes media/network I/O.
 * No plaintext or new durable copy is retained here. */
export class PostgresStorageWitnesses {
  #plans=new WeakMap();
  #entries=new Map();
  #work;
  #kind;
  #tuple;
  #tupleFor;
  #media;
  #clock;
  #ttl;
  constructor({db,groupId,namespace,media,applicationWorkTuple,clock=()=>Date.now(),ttlMs=300000}){
    requireId(groupId);requirePort(db?.applicationWork,['assert']);requirePort(media,['get']);
    check(typeof applicationWorkTuple==='function'&&typeof clock==='function'&&Number.isSafeInteger(ttlMs)&&ttlMs>0&&ttlMs<=300000);
    let origin;try{origin=new URL(namespace?.origin);}catch{check(false);}
    check(origin.protocol==='https:'&&origin.origin===namespace.origin&&!origin.username&&!origin.password&&
      typeof namespace.bucket==='string'&&/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(namespace.bucket)&&same(media.namespace,namespace));
    this.db=db;this.groupId=groupId;this.namespace=Object.freeze(copy(namespace));
    this.#work=db.applicationWork;this.#kind=this.#work.kind??null;this.#tupleFor=applicationWorkTuple;this.#tuple=canonicalJson(applicationWorkTuple(this.#work));
    const tuple=JSON.parse(this.#tuple);
    check(Array.isArray(tuple)&&tuple.length===3&&typeof tuple[0]==='string'&&tuple[0].length>0&&
      Number.isSafeInteger(tuple[1])&&tuple[1]>0&&/^[a-f0-9]{64}$/.test(tuple[2]??''));
    this.#media=media;this.#clock=clock;this.#ttl=ttlMs;
  }
  async owned(){
    check(this.db.applicationWork===this.#work&&(this.#work.kind??null)===this.#kind&&canonicalJson(this.#tupleFor(this.#work))===this.#tuple&&same(this.#media.namespace,this.namespace));
    await this.#work.assert();
    check(this.db.applicationWork===this.#work&&(this.#work.kind??null)===this.#kind&&canonicalJson(this.#tupleFor(this.#work))===this.#tuple&&same(this.#media.namespace,this.namespace));
  }
  key(binding){
    check(binding?.groupId===this.groupId);
    const value=canonicalJson(binding);check(value.length<=131072);return value;
  }
  async stage(binding,targets){
    await this.owned();const key=this.key(copy(binding));
    check(Array.isArray(targets)&&targets.length>0&&targets.length<=4&&new Set(targets.map(t=>t.key)).size===targets.length);
    const saved=targets.map(target=>{
      check(typeof target.key==='string'&&target.key.length<=256&&target.journal?.put?.object_key===target.key);
      return {key:target.key,journal:immutableStorageJournal(target.journal)};
    });
    check(saved.reduce((n,t)=>n+Number(t.journal.put.size),0)<=2097152);
    const plan=Object.freeze(Object.create(null));
    this.#plans.set(plan,{key,targets:saved,createdAt:this.#clock()});return plan;
  }
  async prefetch(plan){
    const pending=this.#plans.get(plan);check(pending);this.#plans.delete(plan);
    await this.owned();check(this.#clock()-pending.createdAt>=0&&this.#clock()-pending.createdAt<=this.#ttl);
    const targets=new Map();
    for(const target of pending.targets){
      await this.owned();
      const object=await this.#media.get(target.key);await this.owned();
      const p=target.journal.put,m=target.journal.metadata,r=target.journal.reservation;
      check(object&&object.key===target.key&&object.size===Number(p.size)&&object.sha256===p.sha256&&
        same(object.httpMetadata,m.http_metadata)&&same(object.customMetadata,m.custom_metadata));
      let bytes;
      try{
        if(typeof object.arrayBuffer==='function')bytes=new Uint8Array(await object.arrayBuffer());
        else {check(typeof object.text==='function');bytes=enc.encode(await object.text());}
        await this.owned();check(bytes.length===Number(p.size)&&bytes.length>0&&bytes.length<=524288&&await hash(bytes)===p.sha256);
        const sealed=dec.decode(bytes),envelope=JSON.parse(sealed);
        check(envelope?.v===1&&envelope.kid===r.key_id&&enc.encode(sealed).length===bytes.length);
        targets.set(target.key,{journal:target.journal,sealed});
      }finally{bytes?.fill(0);}
    }
    await this.owned();check(this.#clock()-pending.createdAt>=0&&this.#clock()-pending.createdAt<=this.#ttl);
    check(this.#entries.has(pending.key)||this.#entries.size<16);
    this.#entries.set(pending.key,{targets,createdAt:pending.createdAt});
  }
  async sealed(binding,key,journal){
    await this.owned();const entry=this.#entries.get(this.key(binding));
    check(entry&&this.#clock()-entry.createdAt>=0&&this.#clock()-entry.createdAt<=this.#ttl);
    const target=entry.targets.get(key);check(target&&same(immutableStorageJournal(journal),target.journal));
    // Recheck after the awaited admission assertion, before returning bytes.
    await this.owned();check(this.#entries.get(this.key(binding))===entry&&
      this.#clock()-entry.createdAt>=0&&this.#clock()-entry.createdAt<=this.#ttl);
    return target.sealed;
  }
  forget(binding){this.#entries.delete(this.key(binding));}
  releaseCommand(command){
    const serialized=canonicalJson(command);
    for(const key of this.#entries.keys()){
      const binding=JSON.parse(key);
      if(binding.kind==='posting'&&canonicalJson(binding.command)===serialized)this.#entries.delete(key);
    }
  }
  releaseSource(job){
    for(const key of this.#entries.keys()){
      const binding=JSON.parse(key);
      if(binding.kind==='source'&&binding.work?.jobId===job.id&&binding.work.owner===job.owner&&
        binding.work.leaseVersion===job.leaseVersion)this.#entries.delete(key);
    }
  }
}
