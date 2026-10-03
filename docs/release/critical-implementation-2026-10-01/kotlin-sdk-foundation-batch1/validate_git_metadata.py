#!/usr/bin/env python3
"""Validate already-fetched official commit/tree objects without lazy downloads."""
import datetime,hashlib,json,os,stat,subprocess,time
from pathlib import Path
P=Path(__file__).resolve().parent
G=Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-metadata-batch2")
COMMIT="ad70ec4617166f1c38e5d2bfd388af71fda14f06";TREE="0af5ce62e3cd8dc4f9441177c3f7db1b26f423fa"
base=["git","-c","credential.helper=","-c","core.hooksPath=/dev/null","-c","http.extraHeader=","-c","protocol.file.allow=never","-c","protocol.ext.allow=never","-C",str(G)]
env={k:os.environ[k] for k in ["PATH","HOME","TMPDIR","LANG","LC_ALL"] if k in os.environ}
env.update({"GIT_TERMINAL_PROMPT":"0","GIT_CONFIG_NOSYSTEM":"1","GIT_CONFIG_GLOBAL":"/dev/null","GIT_NO_LAZY_FETCH":"1"})
commands=[]
def run(args):
    start=time.monotonic();proc=subprocess.run(base+args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=60)
    commands.append({"argv":base+args,"timeout_seconds":60,"elapsed_seconds":round(time.monotonic()-start,3),"exit_code":proc.returncode,"stdout_bytes":len(proc.stdout),"stdout_sha256":hashlib.sha256(proc.stdout).hexdigest(),"stderr":proc.stderr.decode(errors="replace")})
    if proc.returncode:raise ValueError("Git command failed: "+str(args))
    return proc.stdout
def oid(kind,body):return hashlib.sha1(kind.encode()+b" "+str(len(body)).encode()+b"\0"+body).hexdigest()
assert json.loads((P/"official-git-metadata-attempt2.json").read_text())["passed"]
assert run(["rev-parse","FETCH_HEAD"]).decode().strip()==COMMIT
commit=run(["cat-file","commit",COMMIT]);assert oid("commit",commit)==COMMIT
assert commit.splitlines()[0]==("tree "+TREE).encode()
(P/"public-origin/official-git-raw-commit.txt").write_bytes(commit)
tree=run(["cat-file","tree",TREE]);assert oid("tree",tree)==TREE
(P/"public-origin/official-git-raw-root-tree.bin").write_bytes(tree)
ls=run(["ls-tree","-z","-r","-t",COMMIT]);observed={}
for record in ls.split(b"\0"):
    if not record:continue
    header,path=record.split(b"\t",1);mode,kind,sha=header.decode().split(" ")
    name=path.decode();assert name not in observed;observed[name]={"mode":mode,"type":kind,"sha":sha}
api=json.loads((P/"public-origin/official-recursive-tree-attempt3.body").read_text());expected={n["path"]:{k:n[k] for k in ["mode","type","sha"]} for n in api["tree"]}
assert observed==expected
run(["fsck","--strict","--full","--no-dangling",COMMIT])
assert not (G/".git/objects/info/alternates").exists()
identity={};unsafe=[]
for file in sorted((G/".git").rglob("*")):
    s=file.lstat();name=str(file.relative_to(G))
    if stat.S_ISLNK(s.st_mode):unsafe.append(name)
    elif stat.S_ISREG(s.st_mode):
        if s.st_nlink!=1:unsafe.append(name)
        identity[name]={"bytes":s.st_size,"sha256":hashlib.sha256(file.read_bytes()).hexdigest(),"nlink":s.st_nlink}
assert not unsafe
negatives={"actual_raw_commit_byte_drift_rejected":oid("commit",commit+b"changed")!=COMMIT,"actual_raw_tree_byte_drift_rejected":oid("tree",tree+b"changed")!=TREE}
assert all(negatives.values())
result={"passed":True,"observed_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"metadata_repository":str(G),"public_remote":"https://github.com/flutter/flutter.git","raw_commit_sha1":COMMIT,"raw_commit_sha256":hashlib.sha256(commit).hexdigest(),"raw_commit_bytes":len(commit),"raw_root_tree_sha1":TREE,"raw_root_tree_sha256":hashlib.sha256(tree).hexdigest(),"raw_git_entry_count":len(observed),"publisher_API_entry_set_matches_raw_Git_objects":True,"commands":commands,"fresh_git_file_identities":identity,"unsafe_links_or_shared_inode_counts":len(unsafe),"negative_results":negatives,"full_worktree_materialized":False,"lazy_fetch_disabled":True,"local_PGP_signature_verification_performed":False,"scope":"Exact public remote raw commit/tree identity and filtered Git object integrity. Promisor blobs are intentionally absent: fsck is not a proof of full worktree/blob contents. No SDK execution, extraction, patching or acceptance."}
(P/"official-git-metadata-validation.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
print(json.dumps({k:result[k] for k in ["passed","raw_commit_sha1","raw_commit_sha256","raw_root_tree_sha1","raw_git_entry_count","unsafe_links_or_shared_inode_counts","full_worktree_materialized"]}))
