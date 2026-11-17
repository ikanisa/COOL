"""Capture and restore-test the retained Storage volume without stopping it.

The output is an unfenced observational backup. It is not a cutover snapshot:
database/object metadata must match the isolated DB restore before and after two
identical read-only archive reads. No existing container or volume is modified.
"""
from pathlib import Path, PurePosixPath
import hashlib,json,os,subprocess,tarfile,uuid

ROOT=Path('/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-12/burimunsi-live-db-snapshot-001')
D=['/Applications/Docker.app/Contents/Resources/bin/docker','--context','colima-supabase-local']
SOURCE='2b1edd8ffa8f4149445d1af4042d6d10f6dfdb44a6ecd839e8ed0d94ce43abb6'
VOLUME='supabase_storage_local-app'
LABEL='io.collect.storage-readonly-check'
MAX_BYTES=128*1024*1024

def call(args,**kw):
    return subprocess.run(D+args,check=True,capture_output=True,timeout=60,**kw).stdout

def metadata(ident,clone):
    tables=['storage.objects','private.storage_objects','private.storage_put_intents','private.storage_payload_reservations']
    pieces=[]
    for table in tables:
        pieces.append("'%s',(SELECT jsonb_build_object('count',count(*),'hash',encode(sha256(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\\n' ORDER BY to_jsonb(t)::text),''),'UTF8')),'hex')) FROM %s t)"%(table,table))
    query="BEGIN READ ONLY;SET LOCAL TIME ZONE 'UTC';SELECT jsonb_build_object("+','.join(pieces)+");COMMIT;"
    args=['exec',ident,'psql']+(['-h','/tmp'] if clone else [])+['-U','supabase_admin','-d','postgres','-XAtq','-v','ON_ERROR_STOP=1','-c',query]
    return json.loads(call(args,text=True))

def capture(ident,output=None):
    proc=subprocess.Popen(D+['exec',ident,'tar','-C','/mnt','-cf','-','.'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    digest=hashlib.sha256();size=0
    try:
        while chunk:=proc.stdout.read(65536):
            size+=len(chunk)
            if size>MAX_BYTES:raise RuntimeError('storage archive exceeds bound')
            digest.update(chunk)
            if output is not None:output.write(chunk)
        _,err=proc.communicate(timeout=60)
        if proc.returncode:raise RuntimeError('storage archive read failed')
    except BaseException:
        proc.kill();proc.wait();raise
    return digest.hexdigest(),size

def main():
    clone=json.loads((ROOT/'clone.json').read_text())
    assert clone['status']=='ready_for_schema_rehearsal' and clone['network']=='none' and clone['published_ports']==[]
    identity=json.loads(call(['inspect',clone['container_id']],text=True))[0]
    assert identity['Id']==clone['container_id'] and identity['State']['Running'] and identity['HostConfig']['NetworkMode']=='none'
    initial=metadata(SOURCE,False);assert metadata(clone['container_id'],True)==initial
    db=json.loads(call(['inspect',SOURCE],text=True))[0]
    assert db['Id']==SOURCE and db['State']['Running']
    op=str(uuid.uuid4());name='collect-storage-readonly-'+op[:8];helper=None
    archive=ROOT/'storage-objects.private.tar';restore=ROOT/'storage-restore-check'
    assert not archive.exists() and not restore.exists()
    try:
        helper=call(['create','--pull','never','--name',name,'--label',LABEL+'='+op,'--network','none',
            '--read-only','--memory','128m','--cpus','0.5','--user','0',
            '--mount','type=volume,source='+VOLUME+',destination=/mnt,readonly',
            '--entrypoint','/bin/sh',db['Image'],'-c','sleep 600'],text=True).strip()
        check=json.loads(call(['inspect',helper],text=True))[0]
        assert check['Id']==helper and check['Name']=='/'+name and check['Config']['Labels'].get(LABEL)==op
        assert check['HostConfig']['NetworkMode']=='none' and check['HostConfig']['ReadonlyRootfs']
        mounts=check['Mounts'];assert len(mounts)==1 and mounts[0]['Name']==VOLUME and not mounts[0]['RW']
        call(['start',helper])
        fd=os.open(archive,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as stream:
            first,size=capture(helper,stream);stream.flush();os.fsync(stream.fileno())
        second,size2=capture(helper);assert first==second and size==size2
        assert metadata(SOURCE,False)==initial and metadata(clone['container_id'],True)==initial
        restore.mkdir(mode=0o700);files=0
        with tarfile.open(archive,'r:') as tar:
            members=tar.getmembers();assert members
            for member in members:
                p=PurePosixPath(member.name)
                assert not p.is_absolute() and '..' not in p.parts and '\\' not in member.name
                assert member.isdir() or member.isfile()
            tar.extractall(restore,members=members,filter='data')
            for member in members:
                if not member.isfile():continue
                original=tar.extractfile(member);restored=restore/Path(member.name)
                assert original and restored.is_file() and not restored.is_symlink()
                assert hashlib.sha256(original.read()).digest()==hashlib.sha256(restored.read_bytes()).digest()
                files+=1
        receipt={'status':'pass','database_metadata_matches_restored_snapshot':True,
            'read_only_archive_reads_match':True,'restored_files_verified':files,
            'archive_sha256':first,'archive_bytes':size,'source_stopped':False,
            'snapshot_was_unfenced':True,'production_cutover_backup':False}
        fd=os.open(ROOT/'storage-restore-comparison.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as stream:json.dump(receipt,stream,indent=2);stream.write('\n')
        print(json.dumps({k:receipt[k] for k in ('status','restored_files_verified','snapshot_was_unfenced','production_cutover_backup')}))
    finally:
        if helper:
            rows=json.loads(call(['inspect',helper],text=True));item=rows[0]
            if item['Id']==helper and item['Name']=='/'+name and item['Config']['Labels'].get(LABEL)==op:
                call(['rm','-f',helper])

if __name__=='__main__':main()
