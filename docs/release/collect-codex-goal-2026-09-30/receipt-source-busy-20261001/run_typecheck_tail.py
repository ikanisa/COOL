#!/usr/bin/env python3
"""Refresh the failed TS7 invocation only; retain successful unchanged consumers."""
import datetime,hashlib,json,os,pathlib,subprocess
STAGE=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(p,j):p.write_text(json.dumps(j,indent=2)+'\n')
prior=STAGE/'consumers-attempt1';runtime=prior/'runtime';out=STAGE/'consumers-typecheck-tail1';assert not out.exists();out.mkdir()
frozen=json.loads((prior/'frozen-inputs.json').read_text());original_bytes=pathlib.Path(__file__).read_bytes();(out/'executed-runner.py').write_bytes(original_bytes)
def unchanged():
 return all(sha(pathlib.Path(p).read_bytes())==s for kind in ['sources','tools','dependencies']for p,s in frozen[kind].items())and all(os.readlink(p)==s for p,s in frozen['symlinks'].items())
assert unchanged(),'prior successful source/dependency inputs changed'
private={str(p.relative_to(runtime)):sha(p.read_bytes())for p in runtime.rglob('*')if p.is_file()and not p.is_symlink()}
save(out/'runtime-source-manifest.json',private)
node=str(pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve())
tsc='/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/tools/collect-notification-mcp/node_modules/typescript/bin/tsc'
command=[node,tsc,'--ignoreConfig','--noEmit','--target','ES2023','--module','NodeNext','--moduleResolution','NodeNext','--allowImportingTsExtensions','--strict','--noUncheckedIndexedAccess','--exactOptionalPropertyTypes','--skipLibCheck','--types','node','src/unattended_source_busy.test.ts']
start=now();r=subprocess.run(command,cwd=runtime/'tools/collect-notification-mcp',text=True,capture_output=True,timeout=180)
(out/'stdout.log').write_text(r.stdout);(out/'stderr.log').write_text(r.stderr)
association=dict(status='passed'if r.returncode==0 and unchanged()else'failed',argv=command,cwd=str(runtime/'tools/collect-notification-mcp'),started_at=start,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode()),prior_frozen_inputs_sha256=sha((prior/'frozen-inputs.json').read_bytes()),private_runtime_manifest_sha256=sha((out/'runtime-source-manifest.json').read_bytes()),source_and_dependencies_unchanged=unchanged(),private_runtime_unchanged=all(sha((runtime/p).read_bytes())==s for p,s in private.items()),prior_commands_sha256=sha((prior/'commands.json').read_bytes()),refreshed_scope='only failed TS7 invocation; prior successful31 Edge/7 MCP/7 Admin checks reused on exact unchanged consumer sources',fresh_whole_consumer_command=False,complete_candidate=False)
save(out/'result.json',association)
print(json.dumps(association));print(r.stdout+r.stderr);assert association['status']=='passed'and association['private_runtime_unchanged']
