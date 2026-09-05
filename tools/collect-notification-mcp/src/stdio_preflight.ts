import {spawn} from "node:child_process";
import {createInterface} from "node:readline";
import {fileURLToPath} from "node:url";

// Actual MCP transport check. No claim/write/send command or receipt content.
const child=spawn(process.execPath,["--experimental-strip-types",fileURLToPath(new URL("./server.ts",import.meta.url))],{env:process.env,stdio:["pipe","pipe","pipe"]});
child.stderr.resume();
const lines=createInterface({input:child.stdout});
const pending=new Map<number,(value:any)=>void>();
lines.on("line",line=>{try{const value=JSON.parse(line);if(typeof value.id==="number")pending.get(value.id)?.(value);}catch{/* Invalid frames time out safely. */}});
let id=0;
const request=(method:string,params:Record<string,unknown>)=>new Promise<any>((resolve,reject)=>{
  const requestId=++id;
  const timer=setTimeout(()=>{pending.delete(requestId);reject(new Error("MCP_TIMEOUT"));},45000);
  pending.set(requestId,value=>{clearTimeout(timer);pending.delete(requestId);resolve(value);});
  child.stdin.write(JSON.stringify({jsonrpc:"2.0",id:requestId,method,params})+"\n");
});
try{
  const init=await request("initialize",{protocolVersion:"2025-11-25",capabilities:{},clientInfo:{name:"collect-production-read-only-preflight",version:"1"}});
  if(init.result?.serverInfo?.name!=="collect-notification-operator")throw new Error("WRONG_SERVER");
  child.stdin.write(JSON.stringify({jsonrpc:"2.0",method:"notifications/initialized"})+"\n");
  const health=await request("tools/call",{name:"collect_notification_health",arguments:{}});
  if(health.error || health.result?.isError)throw new Error("AUTH_OR_TRANSPORT");
  const list=await request("tools/call",{name:"collect_list_pending_receipts",arguments:{limit:1}});
  if(health.error || health.result?.isError || list.error || list.result?.isError)throw new Error("AUTH_OR_TRANSPORT");
  const h=health.result.structuredContent?.result;
  const rows=list.result.structuredContent?.result;
  if(!h || typeof h.enabled!=="boolean" || !Array.isArray(rows) || rows.length>1)throw new Error("RESPONSE_SHAPE");
  console.log(JSON.stringify({status:"PASS_AUTHENTICATED_STDIO_MCP",tools_called:["collect_notification_health","collect_list_pending_receipts"],queue_enabled:h.enabled,pending_page_count:rows.length,queue_mutations:0,provider_sends:0,credentials_printed:false}));
}catch{
  console.log(JSON.stringify({status:"BLOCKED_STDIO_MCP",queue_mutations:0,provider_sends:0,credentials_printed:false}));process.exitCode=2;
}finally{lines.close();child.kill();}
