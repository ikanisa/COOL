"""Synthetic PostgreSQL/worker integration. The container has no network."""
from pathlib import Path
import json,os,select,socket,subprocess,threading,time,uuid

def qualify(root, out, docker, ident, database, source, sql, result):
    here=Path(__file__).resolve().parent
    generated=subprocess.run(['node',str(here/'native-auto-cross-layer-fixture.mjs')],
        cwd=root,capture_output=True,text=True,check=True,timeout=20)
    fixture=json.loads(generated.stdout)
    path=out/'synthetic-auto-object.json'
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as stream:json.dump(fixture,stream)

    text=(here/'native-auto-contract.sql').read_text()
    marker='END;$storage$;'
    text=text[:text.index(marker)+len(marker)]
    def replace_once(old,new):
        nonlocal text
        if text.count(old)!=1:raise RuntimeError('synthetic source fixture shape changed')
        text=text.replace(old,new)
    replace_once("body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('d',64);",
        "body_sha text:='%s';object_sha text:='%s';fingerprint text:='%s';"%(fixture['bodySha'],fixture['objectSha'],fixture['fingerprint']))
    replace_once("VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');",
        "VALUES(k,'%s',sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,$cipher$%s$cipher$);"%(fixture['sourceFingerprint'],fixture['sealed']))
    replace_once("VALUES('synthetic-private-observation-1',k,repeat('e',64),repeat('f',64),6,sc",
        "VALUES('synthetic-private-observation-1',k,repeat('e',64),'%s',%d,sc"%(fixture['cipherSha'],fixture['cipherSize']))
    replace_once("VALUES(k,'synthetic-private-observation-1',repeat('e',64),repeat('f',64),6,sc",
        "VALUES(k,'synthetic-private-observation-1',repeat('e',64),'%s',%d,sc"%(fixture['cipherSha'],fixture['cipherSize']))
    old="jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64))"
    if text.count(old)!=2:raise RuntimeError('synthetic storage metadata shape changed')
    text=text.replace(old,"jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint','%s')"%fixture['sourceFingerprint'])
    replace_once('source,body_sha,object_sha,4,','source,body_sha,object_sha,%d,'%fixture['plainSize'])
    text+="\nINSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://synthetic-observation.example','private');\nCOMMIT;\n"

    admission=str(uuid.uuid4())
    prefix="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
    record=json.loads(result(prefix+"SELECT private.collect_fence_register('%s'::uuid,'%s','http_collect');COMMIT;"%(admission,source)))
    epoch=record['epoch']
    leaseq=prefix+"SET LOCAL statement_timeout='5s';SET LOCAL lock_timeout='5s';SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('%s'::uuid,%s,'%s');\n\\echo LEASE_READY\n"%(admission,epoch,source)
    lease=subprocess.Popen(docker+['exec','-i',ident,'psql','-h','127.0.0.1','-p','55439','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    try:
        lease.stdin.write(leaseq.encode());lease.stdin.flush();seen=b'';deadline=time.monotonic()+15
        while b'LEASE_READY\n' not in seen:
            if lease.poll() is not None or time.monotonic()>deadline:raise RuntimeError('synthetic HTTP lease unavailable')
            ready,_,_=select.select([lease.stdout],[],[],deadline-time.monotonic())
            if ready:seen+=os.read(lease.stdout.fileno(),8192)
        for key,value in {'ADMISSION_ID':admission,'ADMISSION_EPOCH':str(epoch),'ADMISSION_SOURCE':source}.items():
            text=text.replace('__'+key+'__',value)
        sql(text,timeout=120)
        lease.stdin.write(b'COMMIT;\n\\q\n');lease.stdin.flush();lease.wait(timeout=10)
        if lease.returncode!=0:raise RuntimeError('synthetic HTTP lease close failed')
        closed=json.loads(result(prefix+"SELECT private.collect_fence_close('%s'::uuid,%s,'%s','settled','completed',0,0);COMMIT;"%(admission,epoch,source)))
        if closed['state']!='settled':raise RuntimeError('synthetic HTTP admission not settled')
    finally:
        if lease.poll() is None:lease.terminate();lease.wait(timeout=5)

    stop=threading.Event();listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(12);listener.settimeout(.5)
    port=listener.getsockname()[1];children=[]
    def handle(client):
        process=subprocess.Popen(docker+['exec','-i',ident,'nc','127.0.0.1','55439'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL);children.append(process)
        def into():
            try:
                while data:=client.recv(65536):process.stdin.write(data);process.stdin.flush()
            except (BrokenPipeError,OSError):pass
            finally:
                try:process.stdin.close()
                except OSError:pass
        def outof():
            try:
                while data:=process.stdout.read1(65536):client.sendall(data)
            except (BrokenPipeError,OSError):pass
            finally:
                try:client.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                client.close()
        threading.Thread(target=into,daemon=True).start();threading.Thread(target=outof,daemon=True).start()
    def accept():
        while not stop.is_set():
            try:client,address=listener.accept()
            except socket.timeout:continue
            except OSError:break
            if address[0]!='127.0.0.1':client.close();continue
            threading.Thread(target=handle,args=(client,),daemon=True).start()
    threading.Thread(target=accept,daemon=True).start()
    try:
        env=os.environ.copy();env.update(COLLECT_CI_SYNTHETIC='true',
            BURI_AUTO_SYNTHETIC_DB=f'postgres://postgres:synthetic@127.0.0.1:{port}/{database}',
            BURI_AUTO_SYNTHETIC_FIXTURE=str(path))
        with (out/'native-auto-cross-layer.log').open('x') as log:
            tested=subprocess.run(['/Users/jeanbosco/.local/bin/deno','test','--cached-only','--no-check','-A',
                str(here/'native-auto-cross-layer.test.ts')],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        if tested.returncode:raise RuntimeError('synthetic native worker integration failed; see native-auto-cross-layer.log')
    finally:
        stop.set();listener.close()
        for child in children:
            if child.poll() is None:child.terminate()
