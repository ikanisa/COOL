import {spawn} from "node:child_process";
import {createInterface} from "node:readline";
import {fileURLToPath} from "node:url";
import {queueHealth} from "./queue_health.ts";

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
let check="initialize";
try{
  const args=process.argv.slice(2);
  if(args.length>1 || args.some(arg=>arg!=="--operations"))throw new Error("INVALID_ARGUMENTS");
  const includeOperations=args.includes("--operations");
  const init=await request("initialize",{protocolVersion:"2025-11-25",capabilities:{},clientInfo:{name:"collect-production-read-only-preflight",version:"1"}});
  if(init.result?.serverInfo?.name!=="collect-notification-operator")throw new Error("WRONG_SERVER");
  child.stdin.write(JSON.stringify({jsonrpc:"2.0",method:"notifications/initialized"})+"\n");
  check="collect_notification_health";
  const health=await request("tools/call",{name:"collect_notification_health",arguments:{}});
  if(health.error || health.result?.isError)throw new Error("AUTH_OR_TRANSPORT");
  const h=queueHealth(health.result?.structuredContent?.result);
  check="collect_list_pending_receipts";
  const list=await request("tools/call",{name:"collect_list_pending_receipts",arguments:{limit:1}});
  if(list.error || list.result?.isError)throw new Error("AUTH_OR_TRANSPORT");
  const rows=list.result?.structuredContent?.result;
  if(!Array.isArray(rows) || rows.length>1)throw new Error("RESPONSE_SHAPE");
  const toolsCalled=["collect_notification_health","collect_list_pending_receipts"];
  let operations:Record<string,unknown>={};
  if(includeOperations){
    check="get_collect_health";
    const sample=await request("tools/call",{name:"get_collect_health",arguments:{}});
    if(sample.error || sample.result?.isError)throw new Error("OPERATIONAL_HEALTH_UNAVAILABLE");
    const health=sample.result?.structuredContent?.result;
    if(!health || !["ok","attention","unknown"].includes(health.health_status) || typeof health.sample_fresh!=="boolean")throw new Error("RESPONSE_SHAPE");
    toolsCalled.push("get_collect_health");
    check="list_notification_failures";
    const failure=await request("tools/call",{name:"list_notification_failures",arguments:{limit:1}});
    if(failure.error || failure.result?.isError)throw new Error("FAILURE_LIST_UNAVAILABLE");
    const page=failure.result?.structuredContent?.result;
    if(!Array.isArray(page?.rows) || page.rows.length>1)throw new Error("RESPONSE_SHAPE");
    toolsCalled.push("list_notification_failures");
    let statusChecked=false;
    if(page.rows.length===1){
      const id=page.rows[0]?.notification_id;
      if(typeof id!=="string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))throw new Error("RESPONSE_SHAPE");
      check="get_notification_status";
      const receipt=await request("tools/call",{name:"get_notification_status",arguments:{notification_id:id}});
      if(receipt.error || receipt.result?.isError || typeof receipt.result?.structuredContent?.result?.found!=="boolean")throw new Error("RECEIPT_STATUS_UNAVAILABLE");
      toolsCalled.push("get_notification_status");
      statusChecked=true;
    }
    operations={operational_health_status:health.health_status,operational_sample_fresh:health.sample_fresh,
      notification_failure_page_count:page.rows.length,notification_status_checked:statusChecked};
  }
  console.log(JSON.stringify({status:"PASS_AUTHENTICATED_STDIO_MCP",tools_called:toolsCalled,queue_enabled:h.enabled,pending_page_count:rows.length,...operations,queue_mutations:0,provider_sends:0,credentials_printed:false}));
}catch{
  console.log(JSON.stringify({status:"BLOCKED_STDIO_MCP",blocked_check:check,queue_mutations:0,provider_sends:0,credentials_printed:false}));process.exitCode=2;
}finally{lines.close();child.kill();}
