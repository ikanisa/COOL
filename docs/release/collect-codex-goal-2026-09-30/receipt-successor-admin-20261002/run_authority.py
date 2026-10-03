from pathlib import Path
import datetime, hashlib, json, shutil, subprocess, sys, time

root=Path(__file__).resolve().parents[2]
proof=root/'docs/release/collect-codex-goal-2026-09-30/receipt-successor-admin-20261002'
out=proof/'required-authority-attempt2'
out.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rec=json.loads((proof/'root-integration.json').read_text())
paths=[root/k for k in rec['files']]
paths += [root/k for k in ['AGENTS.md','Makefile','scripts/qa/revolut_design_authority.py','docs/release/revolut-design/authority.json','lib/app/theme/app_theme.dart']]
skill=Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design')
paths += [skill/k for k in ['SKILL.md','references/web-patterns.md','references/component-contracts.md','references/source-and-mac-validation.md','references/typography.md'] if (skill/k).exists()]
make=Path(shutil.which('make'))
paths += [Path(shutil.which('python3')),make,Path(sys.executable),Path(__file__)]
inputs={str(p):{'sha256':sha(p),'resolved_path':str(p.resolve())} for p in paths}
assert sha(skill/'SKILL.md')=='0941cf390b2e77d605ee4877f960440688166534341ae2a3239a990d40127c50'
assert all(sha(root/k)==v['sha256'] for k,v in rec['files'].items())
(out/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
shutil.copy2(Path(__file__),out/'executed-runner.py')
result={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':[str(make),'revolut-design-authority'],'cwd':str(root),'scope':'actual required sole-authority hygiene; selected control/component/tool inputs captured; independently changing proof outputs are outside final candidate freeze','input_count':len(inputs),'exit_code':None,'visual_acceptance':'unverified'}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
start=time.monotonic()
with (out/'stdout.log').open('w') as stdout,(out/'stderr.log').open('w') as stderr:
    process=subprocess.run(result['command'],cwd=root,stdout=stdout,stderr=stderr,timeout=300)
result.update(exit_code=process.returncode,elapsed_seconds=time.monotonic()-start,completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),captured_inputs_unchanged=all(sha(Path(k))==v['sha256'] and str(Path(k).resolve())==v['resolved_path'] for k,v in inputs.items()))
result['accepted']=result['exit_code']==0 and result['captured_inputs_unchanged'] and '[revolut-design-authority] pass' in (out/'stdout.log').read_text()
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
print((out/'stdout.log').read_text()[-3000:])
print((out/'stderr.log').read_text()[-1000:])
sys.exit(0 if result['accepted'] else 1)
