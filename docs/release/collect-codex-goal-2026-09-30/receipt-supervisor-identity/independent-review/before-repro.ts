import { createSupervisorHandler } from "./before-handler.ts";
let calls=0;
const handler=createSupervisorHandler({rpc:async()=>{calls++;throw Error("Unexpected RPC");}});
for(const [name,body]of Object.entries({invalidEscape:String.raw`{"x":"\uXXXX"}`,oversize:"x".repeat(8193)})){
 const response=await handler(new Request("https://example.invalid/supervisor",{method:"POST",headers:{"content-type":"application/json"},body}));
 console.log(JSON.stringify({name,status:response.status,body:await response.json(),rpc_calls:calls}));
}
const pair=await crypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
const spki=new Uint8Array(await crypto.subtle.exportKey("spki",pair.publicKey));
const hex=(bytes:Uint8Array)=>Array.from(bytes,b=>b.toString(16).padStart(2,"0")).join("");
const b64=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes));
const keySha=hex(new Uint8Array(await crypto.subtle.digest("SHA-256",spki)));
const toDer=(raw:Uint8Array)=>{
 const parts=[raw.slice(0,32),raw.slice(32)].map(value=>{let i=0;while(i<31&&value[i]===0)i++;value=value.slice(i);if(value[0]&0x80)value=new Uint8Array([0,...value]);return new Uint8Array([2,value.length,...value]);});
 return new Uint8Array([0x30,parts[0].length+parts[1].length,...parts[0],...parts[1]]);
};
const principal="abcdef00-0000-4000-8000-000000000001";
const request="abcdef00-0000-4000-8000-000000000002".toUpperCase();
const time=new Date().toISOString();const expires=new Date(Date.now()+600000).toISOString();
const envelope={contract_version:1,audience:"collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt",action:"shadow_health",principal_id:principal,request_id:request,issued_at:time,payload:{}};
const raw=new TextEncoder().encode(JSON.stringify(envelope));
const signature=toDer(new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},pair.privateKey,raw)));
let observed=false;
const uppercaseHandler=createSupervisorHandler({rpc:async(name)=>{
 if(name==="receipt_supervisor_key_v1")return{data:{contract_version:1,principal_id:principal,state:"active",scope:"rw_receipt_shadow",public_key_spki_base64:b64(spki),key_sha256:keySha,expires_at:expires},error:null};
 observed=true;
 return{data:{contract_version:1,principal_id:principal,request_id:request.toLowerCase(),action:"shadow_health",observed_at:time,expires_at:expires,scope:"rw_receipt_shadow",mode:"Shadow",business_handled:false,financial_action:false,send_action:false,sample_valid_until:new Date(Date.parse(time)+60000).toISOString(),queued_count:0,unknown_count:0,failed_no_send_count:0,dispatch_enabled:false},error:null};
}});
const response=await uppercaseHandler(new Request("https://example.invalid/supervisor",{method:"POST",headers:{"content-type":"application/json","X-Collect-Supervisor-Key-Id":keySha,"X-Collect-Supervisor-Signature":b64(signature)},body:raw}));
console.log(JSON.stringify({name:"uppercase-request-uuid",status:response.status,body:await response.json(),service_observe_called:observed}));
