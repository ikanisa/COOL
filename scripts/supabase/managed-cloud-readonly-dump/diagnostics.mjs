// A deliberately small, value-checked vocabulary. No paths, SQL, stderr text,
// database contents, credentials, exception messages or arbitrary strings.
const PHASES=new Set(['headroom_check','headroom_checked','dispatch_recorded','tools_pin_started','tools_pinned','credentials_read_started','credentials_loaded','snapshot_open_started','snapshot_exported','artifact_creation_started','artifacts_opened',
 'dump_started','dump_stream_refused','dump_stop_unconfirmed','dump_exit_refused','dump_stderr_refused','snapshot_recheck','pre_toc_sync','toc_authentication_started',
 'toc_process_started','toc_total_bound_refused','toc_line_bound_refused','toc_stream_refused','toc_missing_schema_refused',
 'toc_timeout','toc_stop_unconfirmed','toc_exit_refused','toc_stderr_refused','toc_validated','promotion_started','promotion_readback','journal_completion_started','journal_completed']);
const CLOSED=new Set(['dump_process_closed','toc_process_closed']);
const SIGNALS=new Set(['SIGABRT','SIGALRM','SIGBUS','SIGFPE','SIGHUP','SIGILL','SIGINT','SIGKILL','SIGPIPE','SIGQUIT','SIGSEGV','SIGSYS','SIGTERM','SIGTRAP','SIGUSR1','SIGUSR2','SIGXCPU','SIGXFSZ','OTHER']);
export const MAX_DIAGNOSTIC_BYTES=16384,MAX_DIAGNOSTIC_EVENTS=48;
export function normalizedSignal(signal){return signal==null?null:SIGNALS.has(signal)?signal:'OTHER';}
export function normalizedExitCode(code){return Number.isInteger(code)&&code>=0&&code<=255?code:null;}
export function cleanDiagnostic(v){
 if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.phase!=='string')return null;
 const keys=Object.keys(v).sort().join(',');
 if(PHASES.has(v.phase)&&keys==='phase')return {phase:v.phase};
 if(CLOSED.has(v.phase)&&keys==='exitCode,phase,signal,stderrBytes'&&
  (v.exitCode===null||Number.isInteger(v.exitCode)&&v.exitCode>=0&&v.exitCode<=255)&&
  (v.signal===null||SIGNALS.has(v.signal))&&Number.isSafeInteger(v.stderrBytes)&&v.stderrBytes>=0)
  return {phase:v.phase,exitCode:v.exitCode,signal:v.signal,stderrBytes:v.stderrBytes};
 return null;
}
export function decodeDiagnostics(bytes){
 if(!Buffer.isBuffer(bytes)||bytes.length>MAX_DIAGNOSTIC_BYTES)return [];const text=bytes.toString('utf8'),last=text.lastIndexOf('\n');
 const lines=last>=0?text.slice(0,last).split('\n'):[];if(lines.length>MAX_DIAGNOSTIC_EVENTS)return [];const out=[];
 for(const line of lines){if(line.length>512)return [];let v;try{v=JSON.parse(line);}catch{return [];}const safe=cleanDiagnostic(v);if(!safe)return [];out.push(safe);}
 return out;
}
