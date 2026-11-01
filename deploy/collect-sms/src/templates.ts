import type {Context} from "npm:hono@4.13.13";
import type {AppEnv,Env,Kind} from "./types.ts";
import {application} from "./auth.ts";
import {createMessage} from "./messages.ts";
import {ApiError,canonical,integer,isoNow,kind,object,segmentEstimate,sha256,string,timestamp} from "./util.ts";
export interface TemplateRow{application_id:string;template_key:string;version:number;locale:string;kind:Kind;body:string;schema_json:string;digest:string;status:string;created_at:string;}
export function locale(value:unknown){const v=string(value,'locale',2,2);if(!['en','rw','fr'].includes(v))throw new ApiError(400,'unsupported_locale','Supported locales are en, rw, fr');return v;}
function templateSchema(body:string,schema:unknown) {
 const s=object(schema,'variables');const keys=Object.keys(s);
 if(keys.length>30)throw new ApiError(400,'too_many_variables','At most 30 variables');
 for(const k of keys)if(!/^[a-z][a-z0-9_]{0,49}$/.test(k)||!['text','rwf','integer','datetime'].includes(String(s[k])))throw new ApiError(400,'invalid_template_schema','Use variable names and text, rwf, integer or datetime types');
 const tokens=[...body.matchAll(/\{\{([a-z][a-z0-9_]{0,49})\}\}/g)].map(m=>m[1]!);
 if(/[{}]/.test(body.replace(/\{\{[a-z][a-z0-9_]{0,49}\}\}/g,''))||keys.some(k=>!tokens.includes(k))||tokens.some(k=>!Object.hasOwn(s,k)))throw new ApiError(400,'invalid_template','Every placeholder must have exactly one schema definition; unused definitions are not allowed');
 return s;
}
/** Deterministic formatting. No expressions, HTML, eval or model-generated values. */
export function renderTemplate(t:TemplateRow,variables:unknown) {
 const values=object(variables,'variables'),schema=templateSchema(t.body,JSON.parse(t.schema_json));
 if(Object.keys(values).length!==Object.keys(schema).length||Object.keys(values).some(k=>!Object.hasOwn(schema,k)))throw new ApiError(400,'template_variables','Provide exactly the declared variables');
 const prepared:Record<string,string>={};
 for(const [k,type]of Object.entries(schema)){
  if(type==='text'){prepared[k]=string(values[k],k,1,160);if(/[\u0000-\u001f\u007f]/.test(prepared[k]!))throw new ApiError(400,'template_variables','Text variables must be single-line printable values');}
  else if(type==='datetime'){const iso=timestamp(values[k],k);const local=new Date(Date.parse(iso)+7200000).toISOString();prepared[k]=local.slice(0,10)+' '+local.slice(11,16)+' CAT';}
  else{const v=integer(values[k],k,type==='rwf'?0:-Number.MAX_SAFE_INTEGER);prepared[k]=type==='rwf'?'RWF '+String(v).replace(/\B(?=(\d{3})+(?!\d))/g,','):String(v);}
 }
 const text=t.body.replace(/\{\{([a-z][a-z0-9_]{0,49})\}\}/g,(_,k)=>prepared[k]!);
 string(text,'rendered text',1,2000);
 return {text,segments_estimate:segmentEstimate(text),template_key:t.template_key,version:t.version,locale:t.locale,template_digest:t.digest};
}
export async function getTemplate(env:Env,applicationId:string,key:string,version:number,lang:string,requirePublished=true){
 const t=await env.DB.prepare('SELECT * FROM sms_templates WHERE application_id=? AND template_key=? AND version=? AND locale=?').bind(applicationId,key,version,lang).first<TemplateRow>();
 if(!t)throw new ApiError(404,'template_not_found','Exact template version/locale not found');
 if(requirePublished&&t.status!=='published')throw new ApiError(409,'template_unpublished','Publish the reviewed version explicitly before sending');return t;
}
export async function createTemplate(c:Context<AppEnv>,b:Record<string,unknown>){
 const workload=kind(b.kind),p=application(c,'messages:write',workload),key=string(b.template_key,'template_key',1,80),version=integer(b.version,'version',1,1000000),lang=locale(b.locale),body=string(b.body,'body',1,2000);
 if(!/^[a-z0-9][a-z0-9_.-]*$/.test(key))throw new ApiError(400,'invalid_template_key','Use a simple lowercase template identifier');
 const schema=templateSchema(body,b.variables),digest=await sha256(canonical({key,version,lang,body,kind:workload,schema}));
 const old=await c.env.DB.prepare('SELECT digest FROM sms_templates WHERE application_id=? AND template_key=? AND version=? AND locale=?').bind(p.id,key,version,lang).first();
 if(old&&old.digest!==digest)throw new ApiError(409,'template_version_conflict','Create a new version rather than changing an existing one');
 try{await c.env.DB.prepare("INSERT INTO sms_templates VALUES(?,?,?,?,?,?,?,?, 'draft',?) ON CONFLICT(application_id,template_key,version,locale) DO UPDATE SET digest=excluded.digest").bind(p.id,key,version,lang,workload,body,canonical(schema),digest,isoNow()).run();}catch(error){const raced=await c.env.DB.prepare('SELECT digest FROM sms_templates WHERE application_id=? AND template_key=? AND version=? AND locale=?').bind(p.id,key,version,lang).first();if(raced&&raced.digest!==digest)throw new ApiError(409,'template_version_conflict','Another request already defined this immutable version');throw error;}
 return c.json({template_key:key,version,locale:lang,digest,status:(await getTemplate(c.env,p.id,key,version,lang,false)).status},201);
}
export async function listTemplates(c:Context<AppEnv>){const p=application(c,'messages:read');const result=await c.env.DB.prepare('SELECT template_key,version,locale,kind,status,digest,created_at FROM sms_templates WHERE application_id=? ORDER BY template_key,version DESC,locale LIMIT 500').bind(p.id).all();return c.json({templates:result.results});}
export async function templateAction(c:Context<AppEnv>,b:Record<string,unknown>){
 const p=application(c,'messages:write'),key=string(c.req.param('key'),'key',1,80),v=integer(Number(c.req.param('version')),'version',1,1000000),lang=locale(c.req.param('locale'));
 const t=await getTemplate(c.env,p.id,key,v,lang,false);application(c,'messages:write',t.kind);
 const action=c.req.param('action');
 if(action==='publish'){
  if(b.confirm!=='publish_reviewed_template')throw new ApiError(400,'confirmation_required','Confirm publish_reviewed_template after checking wording and variables');
  await c.env.DB.prepare("UPDATE sms_templates SET status='published' WHERE application_id=? AND template_key=? AND version=? AND locale=?").bind(p.id,key,v,lang).run();return c.json({template_key:key,version:v,locale:lang,status:'published'});
 }
 const rendered=renderTemplate(t,b.variables);
 if(action==='preview')return c.json({...rendered,published:t.status==='published'});
 if(action!=='send')throw new ApiError(404,'not_found','Template action not found');
 if(t.status!=='published')throw new ApiError(409,'template_unpublished','Publish the reviewed version before sending');
 return createMessage(c,{kind:t.kind,to:b.to,text:rendered.text,not_after:b.not_after,metadata:{template_key:key,template_version:v,locale:lang,template_digest:t.digest}});
}
