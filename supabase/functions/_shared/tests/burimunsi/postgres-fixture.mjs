import {spawn,spawnSync} from 'node:child_process';
import {realpathSync,statSync} from 'node:fs';
import {basename,dirname,isAbsolute,join} from 'node:path';

// Only the fixture launcher supplies these inputs. Each test worker verifies
// the private socket and owned cluster before submitting its test statements.
export function loadBuriPostgresFixture() {
  const launchRoot = process.env.COLLECT_BURI_FIXTURE_ROOT;
  const executable = process.env.COLLECT_BURI_FIXTURE_PSQL;
  const port = process.env.COLLECT_BURI_FIXTURE_PORT;
  if ([launchRoot,executable,port].every(value=>value===undefined)) return null;

  const socket = join(launchRoot??'', 'socket');
  if (!launchRoot || !isAbsolute(launchRoot) || realpathSync(launchRoot)!==launchRoot ||
      !/^collect-buri-fixture-[A-Za-z0-9]+$/.test(basename(launchRoot)) ||
      !executable || !isAbsolute(executable) || realpathSync(executable)!==executable ||
      basename(executable)!=='psql' ||
      !/^[0-9]{5}$/.test(port??'') || Number(port)<20000 || Number(port)>=60000 ||
      realpathSync(socket)!==socket || dirname(socket)!==launchRoot) {
    throw Error('SYNTHETIC_BURI_FIXTURE_CONFIG_REFUSED');
  }
  for (const path of [launchRoot,socket]) {
    const info = statSync(path);
    if (!info.isDirectory() || info.uid!==process.getuid() || (info.mode & 0o777)!==0o700) {
      throw Error('SYNTHETIC_BURI_FIXTURE_PATH_REFUSED');
    }
  }

  const env = {PATH:'/usr/bin:/bin',LC_ALL:'C',PGCONNECT_TIMEOUT:'5'};
  const argumentsFor = (user,args) => {
    if (!['postgres','supabase_admin'].includes(user)) throw Error('SYNTHETIC_BURI_FIXTURE_USER_REFUSED');
    return ['-h',socket,'-p',port,'-U',user,'-d','postgres','-X','-w','-v','ON_ERROR_STOP=1',...args];
  };
  const run = (user,args,input) => spawnSync(executable,argumentsFor(user,args),{
    input,env,encoding:'utf8',maxBuffer:1024*1024,timeout:20000,
  });
  const identity = run('postgres',['-Atq','-c',`SELECT
    (inet_server_addr() IS NULL AND current_setting('listen_addresses')='' AND current_user='postgres')::text
    ||':'||current_setting('data_directory')||':'||(current_setting('server_version_num')::int/10000)::text`]);
  if (identity.status!==0 || identity.stdout.trim()!==`true:${join(launchRoot,'data')}:17`) {
    throw Error('SYNTHETIC_BURI_POSTGRES_IDENTITY_MISMATCH');
  }
  return {
    run,
    start: (user,args) => spawn(executable,argumentsFor(user,args),{env,stdio:['pipe','pipe','pipe']}),
  };
}
