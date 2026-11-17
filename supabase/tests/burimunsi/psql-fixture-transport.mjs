// TEST ONLY. PostgreSQL transport for the already-owned network-none native
// qualification database. No TCP port, lifecycle, provider or production target.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
function literal(value){
 if(value===null||value===undefined)return 'NULL';
 if(value instanceof Date)return quote(value.toISOString());
 if(typeof value==='boolean')return value?'true':'false';
 if(typeof value==='number'){if(!Number.isSafeInteger(value))throw Error('fixture_integer_required');return String(value);}
 if(Array.isArray(value))return 'ARRAY['+value.map(literal).join(',')+']';
 return quote(typeof value==='object'?JSON.stringify(value):value);
}
function bind(text,values){
 let result='',index=0;
 while(index<text.length){
  if(text[index]==="'"){const start=index++;for(;;){if(index>=text.length)throw Error('fixture_sql_quote');
    if(text[index++]==="'"){if(text[index]==="'"){index++;continue;}break;}}
   result+=text.slice(start,index);continue;}
  const match=/^\$(\d+)\b/.exec(text.slice(index));
  if(match){const number=Number(match[1])-1;if(number>=values.length)throw Error('fixture_sql_parameter');result+=literal(values[number]);index+=match[0].length;}
  else result+=text[index++];
 }
 return result;
}
const helper=`CREATE FUNCTION pg_temp.collect_fixture_query(p_sql text,p_rows boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER AS $fixture$
DECLARE result jsonb; affected bigint;
BEGIN
 IF p_rows THEN
  EXECUTE 'WITH __collect_fixture_rows AS ('||p_sql||') SELECT jsonb_build_object(''rows'',coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb),''count'',count(*)) FROM __collect_fixture_rows r' INTO result;
 ELSE
  EXECUTE p_sql; GET DIAGNOSTICS affected=ROW_COUNT;
  result:=jsonb_build_object('rows','[]'::jsonb,'count',affected);
 END IF;
 RETURN result;
END;$fixture$;`;

export function fixturePool({docker,host,container,database,record}){
 if(typeof docker!=='string'||!docker.startsWith('/')||host!=='unix:///Volumes/SupaRuntime/.colima/supabase-local/docker.sock'
  ||!/^[a-f0-9]{64}$/.test(container)||!/^collect_burimunsi_[a-f0-9]{24}_test$/.test(database)||typeof record!=='function')throw Error('owned_isolated_fixture_required');
 const children=new Set(),closed=[],exits=[];
 async function reserve(){
  const child=spawn(docker,['--host',host,'exec','-i',container,'psql','-h','/tmp','-U','postgres','-d',database,
   '-XqAt','--no-password','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
  children.add(child);let buffer='',pending=null,released=false,queue=Promise.resolve(),stderr='';
  child.stderr.on('data',bytes=>{stderr+=bytes.toString();if(stderr.length>1024*1024)stderr=stderr.slice(-1024*1024);});
  child.stdout.on('data',bytes=>{
   buffer+=bytes.toString();if(buffer.length>8*1024*1024){pending?.reject(Error('fixture_response_too_large'));pending=null;return;}
   for(let end;(end=buffer.indexOf('\n'))!==-1;){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
    if(!pending)continue;
    if(line===pending.end){const current=pending;pending=null;clearTimeout(current.timer);current.resolve(current.lines);}
    else pending.lines.push(line);
   }
  });
  child.on('error',error=>{pending?.reject(error);pending=null;});
  const exited=new Promise(resolve=>child.on('close',code=>{
   children.delete(child);record({kind:'psql_exit',pid:child.pid,code,stderr});
   if(pending){clearTimeout(pending.timer);pending.reject(Error('fixture_psql_exited'));pending=null;}resolve(code);
  }));
  exits.push(exited);
  const dispatch=sql=>{
   if(released||pending)throw Error('fixture_connection_closed_or_busy');
   return new Promise((resolve,reject)=>{
    const end='COLLECT_FIXTURE_'+randomUUID().replaceAll('-','');
    const timer=setTimeout(()=>{if(pending?.end===end){pending=null;reject(Error('fixture_sql_unconfirmed_no_replay'));}},20000);
    pending={resolve,reject,end,timer,lines:[]};child.stdin.write(sql+'\n\\echo '+end+'\n');
   });
  };
  await dispatch("SET statement_timeout='15s';SET lock_timeout='5s';\n"+helper);
  const unsafe=(text,values=[])=>{
   const operation=queue.then(async()=>{
    let sql=bind(text,values).trim().replace(/;\s*$/,'');
    if(/^SHOW (transaction_read_only|transaction_isolation)$/i.test(sql)){
     const name=sql.slice(5);sql='SELECT current_setting('+quote(name)+') AS '+name;
    }
    const control=/^(?:BEGIN|COMMIT|ROLLBACK|SET (?:LOCAL |TRANSACTION )|RESET )/i.test(sql);
    const rows=/^(?:SELECT|WITH)\b/i.test(sql)||/\bRETURNING\b/i.test(sql);
    // The existing psql sentinel is the positive control-command ACK.
    // A dummy SELECT after BEGIN would consume the first query and prevent the
    // ORIGINAL caller from setting RR READ ONLY before its first real query.
    const command=control?sql+';':
     'SELECT pg_temp.collect_fixture_query('+quote(sql)+','+(rows?'true':'false')+');';
    const lines=await dispatch(command),payload=lines.filter(line=>line.trim());
    if(control){
     if(payload.length!==0)throw Error('fixture_control_response_shape');
     const acknowledged=[];Object.defineProperty(acknowledged,'count',{value:0});return acknowledged;
    }
    if(payload.length!==1)throw Error('fixture_response_shape');
    const value=JSON.parse(payload[0]);
    if(!Array.isArray(value.rows)||!Number.isSafeInteger(value.count))throw Error('fixture_response_invalid');
    // postgres3.4.7 projects the actual timestamptz clock as Date. Other source
    // timestamps are app TEXT and must retain their original bytes.
    for(const row of value.rows)if(typeof row.allocation_at==='string')row.allocation_at=new Date(row.allocation_at);
    Object.defineProperty(value.rows,'count',{value:value.count});return value.rows;
   });
   queue=operation.catch(()=>{});return operation;
  };
  const connection=(parts,...values)=>unsafe(parts.reduce((sql,part,index)=>sql+(index?'$'+index:'')+part,''),values);
  connection.unsafe=unsafe;
  connection.fixtureScript=text=>{const operation=queue.then(()=>dispatch(text));queue=operation.catch(()=>{});return operation;};
  connection.release=()=>{
   if(released)return;released=true;child.stdin.end('\\q\n');closed.push(exited.then(code=>{if(code!==0)throw Error('fixture_psql_cleanup_failed');}));
  };
  return connection;
 }
 const pool={reserve,async begin(options,fn){if(typeof options==='function'){fn=options;options='';}
  const sql=await reserve();let ended=false;
  try{await sql.unsafe('BEGIN '+options);const result=await fn(sql);await sql.unsafe('COMMIT');ended=true;return result;}
  catch(error){try{await sql.unsafe('ROLLBACK');ended=true;}catch{}throw error;}
  finally{if(ended)sql.release();}
 },async end(){for(const child of children)if(!child.stdin.writableEnded&&!child.stdin.destroyed)child.stdin.end('\\q\n');await Promise.all(closed);
  const codes=await Promise.all(exits);if(codes.some(code=>code!==0))throw Error('fixture_psql_cleanup_failed');}};
 return pool;
}
