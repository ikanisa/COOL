from pathlib import Path
import subprocess,json,hashlib,os,datetime
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent;DENO=ROOT/'.cache/roster-deno-2.5.6-20260929/deno';STAGE=ROOT/'.cache/ai-import-minimization-batch1/corrected-source/source';BASE=OUT/'before'
OWNED=['supabase/functions/_shared/openai_roster.ts','supabase/functions/_shared/openai_roster_test.ts','supabase/functions/prepare-roster-import/handler_test.ts'];FILES=[r['path'] for r in json.loads((OUT/'source-before.json').read_text())['files']]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def cohort(base):return {p:sha(base/p) for p in FILES}
report={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'current_before':cohort(ROOT),'stage_before':cohort(STAGE),'baseline_before':cohort(BASE),'runtime_before':sha(DENO),'executed_runner_before':sha(Path(__file__)),'commands':[]}
env={'PATH':os.defpath,'DENO_NO_UPDATE_CHECK':'1','NO_COLOR':'1'}
def run(label,command,cwd):
 with (OUT/(label+'.stdout')).open('xb') as out,(OUT/(label+'.stderr')).open('xb') as err:
  r=subprocess.run([str(DENO),*command],cwd=cwd,env=env,stdout=out,stderr=err,timeout=30)
 report['commands'].append({'label':label,'command':[str(DENO),*command],'cwd':str(cwd),'exit_code':r.returncode})
 return r.returncode
assert run('baseline-owned-lint',['lint','--no-config',*OWNED],BASE)==1
old=(OUT/'baseline-owned-lint.stderr').read_text();new=(OUT/'corrected-source/lint.stderr').read_text();assert old.count('error[require-await]')==new.count('error[require-await]')==3
for line in [149,161,347]:assert f'handler_test.ts:{line}:19' in old or f'handler_test.ts:{line}:10' in old or f'handler_test.ts:{line}:12' in old
assert run('changed-helper-lint',['lint','--no-config',*OWNED[:2]],STAGE)==0
assert run('owned-format-check',['fmt','--check',*OWNED],STAGE)==0
report.update(current_after=cohort(ROOT),stage_after=cohort(STAGE),baseline_after=cohort(BASE),runtime_after=sha(DENO),executed_runner_after=sha(Path(__file__)))
assert report['current_before']==report['current_after']==report['stage_before']==report['stage_after'];assert report['baseline_before']==report['baseline_after'];assert report['runtime_before']==report['runtime_after'];assert report['executed_runner_before']==report['executed_runner_after']
report.update(status='scoped_pass_with_preexisting_handler_lint_open',new_lint_errors=0,preexisting_handler_require_await=3,source_unchanged=True,tool_unchanged=True,no_rule_suppressions=True,full_handler_lint_pass=False,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
(OUT/'lint-format-followup.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','new_lint_errors','preexisting_handler_require_await','source_unchanged','tool_unchanged','full_handler_lint_pass']}))
