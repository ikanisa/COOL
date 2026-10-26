import {acquireEmailProof} from '../src/human_login.mjs';
import {open} from 'node:fs/promises';
import {AdminHttp} from '../src/http_client.mjs';
import {BrokerServer,readConfig} from '../src/broker.mjs';
import {privateDirectory} from '../src/private_state.mjs';

// Interactive authentication is deliberately absent from MCP and its arguments/environment.
async function terminal() {
  const handle=await open('/dev/tty','r+');
  // A real TTY is required so email codes cannot be accidentally read from a pipe.
  const tty=await import('node:tty');
  if(!tty.isatty(handle.fd))throw new Error('interactive_terminal_required');
  const reader=new tty.ReadStream(handle.fd,{autoClose:false}),writer=new tty.WriteStream(handle.fd,{autoClose:false});
  async function prompt(label,{secret=false,signal=lifetime.signal}={}) {
    if(signal.aborted)throw new Error('cancelled');
    writer.write(label);reader.setRawMode(true);reader.resume();let text='';
    return new Promise((resolve,reject)=>{
      const onData=chunk=>{
        for(const character of chunk.toString('utf8')) {
          if(character==='\x03'){finish();reject(new Error('cancelled'));return;}
          if(character==='\r'||character==='\n'){finish();writer.write('\n');resolve(text);return;}
          if(character==='\x7f'){text=text.slice(0,-1);if(!secret)writer.write('\b \b');}
          else if(character>=' '&&character!=='\x7f'&&text.length<512){text+=character;if(!secret)writer.write(character);}
        }
      };
      const aborted=()=>{finish();reject(new Error('cancelled'));};
      const finish=()=>{reader.off('data',onData);signal.removeEventListener('abort',aborted);reader.setRawMode(false);reader.pause();};reader.on('data',onData);signal.addEventListener('abort',aborted,{once:true});
    });
  }
  return {prompt,write:text=>writer.write(text),close:async()=>{reader.destroy();writer.destroy();await handle.close().catch(()=>{});}};
}
let http,broker,tty;
const lifetime=new AbortController();
const cancel=()=>lifetime.abort();
process.once('SIGINT',cancel);process.once('SIGTERM',cancel);
try {
  const args=process.argv.slice(2);
  if(args.length!==6||args[0]!=='--config'||args[2]!=='--config-sha256'||args[4]!=='--state-dir')throw new Error('exact_arguments_required');
  if(process.env.NODE_TLS_REJECT_UNAUTHORIZED==='0')throw new Error('normal_tls_verification_required');
  const config=await readConfig(args[1],args[3]);await privateDirectory(args[5]);process.chdir(args[5]);
  tty=await terminal();http=new AdminHttp({origin:config.origin});
  tty.write('Collect Supabase operator. Sign in with an email code. Codes stay in this terminal; no Messages action occurs here.\n');
  const email=await tty.prompt('Email: ');
  const requestCode=async purpose=>{
    const proof=await acquireEmailProof({origin:config.origin,purpose},{signal:lifetime.signal,onPairing:({parentUrl,descriptor})=>{
      tty.write('Open '+parentUrl+' in your browser, paste this public pairing descriptor, and complete the security challenge yourself. No credential is copied from the browser.\n');
      tty.write(JSON.stringify(descriptor)+'\n');
    }});
    return purpose==='sign_in'?http.requestEmailSignIn(email,proof,{signal:lifetime.signal}):http.requestEmailVerification(proof,{signal:lifetime.signal});
  };
  const enterCode=async(challenge,initial)=>{
    tty.write(challenge.delivery_status==='unknown'?'The email request is unconfirmed. If a code arrives, enter it below; no email is resent automatically.\n':'Check your email for the code.\n');
    for(let attempt=0;attempt<5;attempt++){
      let code=await tty.prompt('Six-digit email code: ',{secret:true});
      try{return await (initial?http.verifyEmailSignIn(challenge.challenge_id,code,{signal:lifetime.signal}):http.verifyEmail(challenge.challenge_id,code,{signal:lifetime.signal}));}
      catch(error){if(error.code!=='invalid_credentials'||error.outcomeUnknown||attempt===4)throw error;tty.write('That code was not accepted. Enter the code again; no new email was requested.\n');}
      finally{code='';}
    }
  };
  await enterCode(await requestCode('sign_in'),true);
  const verify=async()=>enterCode(await requestCode('sensitive'),false);
  broker=new BrokerServer({stateDir:args[5],http});
  tty.write(JSON.stringify(await broker.start())+'\n');
  for(;;) {
    const command=await tty.prompt('status / verify / quit: ');
    if(command==='quit')break;
    if(command==='status'){await http.refresh();tty.write(JSON.stringify(http.metadata())+'\n');}
    else if(command==='verify'){try{await verify();tty.write('Email verified for this session. Previous claims and content remain fenced; resolve original operations before proceeding.\n');}catch{tty.write('Email verification could not be confirmed. No automatic resend or verification retry occurred. Use status to recheck the original session.\n');}}
    else tty.write('Use status, verify or quit.\n');
  }
} catch {if(tty)tty.write('Operator authentication or broker admission failed; no credential creation or automatic retry occurred.\n');else process.stderr.write('Collect operator requires the reviewed config, private state directory and an interactive terminal.\n');process.exitCode=1;}
finally {process.off('SIGINT',cancel);process.off('SIGTERM',cancel);lifetime.abort();if(http?.snapshot())await http.logout().catch(()=>http.clear());await broker?.close().catch(()=>{});http?.clear();await tty?.close().catch(()=>{});}
