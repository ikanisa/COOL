from pathlib import Path
import re,hashlib,json,textwrap,difflib,datetime,shutil
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');OUT=ROOT/'docs/release/critical-implementation-2026-10-01/ai-import-fixture-lint-batch1';name='supabase/functions/prepare-roster-import/handler_test.ts';old=(ROOT/name).read_text();new=(OUT/'proposed-handler_test.ts').read_text()
shutil.copyfile('/tmp/collect_fixture_proposal.py',OUT/'proposal-preparation-runner.py')
(OUT/'proposal-preparation-failure.json').write_text(json.dumps({'status':'failed_own_comparison','source_mutations':[],'cause':'Dedented byte comparison was too strict: Deno formatter added a block around existing single-line sourceError early return and wrapped consent assertion with trailing comma. Both are recorded before review; no root source change occurred.'},indent=2)+'\n')
def tokens(body):
 parts=re.findall(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`|//[^\n]*|/\*[\s\S]*?\*/|\s+|.',body)
 return ''.join(p for p in parts if not p.isspace() and not p.startswith('//') and not p.startswith('/*'))
configs=[('authenticate','    authenticate: async () => {\n','    },\n    configuration:','    authenticate: () =>\n      fixturePromise(() => {\n','      }),\n    configuration:'),('rpc','    rpc: async (name, args) => {\n','    },\n    // This fixture','    rpc: (name, args) =>\n      fixturePromise(() => {\n','      }),\n    // This fixture'),('fetch','    fetch: async (_url, init) => {\n','    },\n  };\n  return {','    fetch: (_url, init) =>\n      fixturePromise(() => {\n','      }),\n  };\n  return {')]
checks=[]
for label,a,b,c,d in configs:
 x=old.split(a,1)[1].split(b,1)[0];y=new.split(c,1)[1].split(d,1)[0];tx=tokens(x);ty=tokens(y)
 normalized=re.sub(r',(?=\))','',ty)
 if label=='rpc':
  assert normalized.count('if(state.sourceError){return{data:null,error:state.sourceError};}')==1
  normalized=normalized.replace('if(state.sourceError){return{data:null,error:state.sourceError};}','if(state.sourceError)return{data:null,error:state.sourceError};',1)
 assert tx==normalized
 checks.append({'callback':label,'body_has_await':bool(re.search(r'\bawait\b',tx)),'original_tokens_sha256':hashlib.sha256(tx.encode()).hexdigest(),'candidate_normalized_tokens_sha256':hashlib.sha256(normalized.encode()).hexdigest(),'tokens_same_after_explicit_formatter_only_normalizations':True,'normalization':'whitespace/comments; trailing argument comma; one formatter-added sourceError if block for rpc only'})
 assert not checks[-1]['body_has_await']
(OUT/'body-preservation.json').write_text(json.dumps({'callbacks':checks,'method':'Lexical comparison preserving string values and token order; not a general AST proof','formatter_only_differences':['Existing sourceError if early return gains braces; same predicate and return expression','Existing consent assertion wraps and gains trailing comma'],'same_event_and_assertion_order':True,'same_return_and_error_conditions':True,'helper_semantics':'body() runs before Promise.resolve in the same call stack; synchronous exceptions become Promise.reject in catch; no artificial await/deferred then or test suppression','current_return_types':['plain actor object','plain SQL result/error object','Response'],'generic_identity_limit':'Current bodies do not return thenables/promises; Promise.resolve would return an existing Promise unchanged for a different future T, whereas an async wrapper returns a distinct Promise'},indent=2)+'\n')
helper='''function fixturePromise<T>(body: () => T): Promise<T> {
  try {
    return Promise.resolve(body());
  } catch (error) {
    return Promise.reject(error);
  }
}
'''
raw=old.replace('function fixture() {',helper+'function fixture() {',1)
for a,b in [('    authenticate: async () => {','    authenticate: () => fixturePromise(() => {'),('    },\n    configuration:','    }),\n    configuration:'),('    rpc: async (name, args) => {','    rpc: (name, args) => fixturePromise(() => {'),('    },\n    // This fixture','    }),\n    // This fixture'),('    fetch: async (_url, init) => {','    fetch: (_url, init) => fixturePromise(() => {'),('    },\n  };\n  return {','    }),\n  };\n  return {')]:assert raw.count(a)==1;raw=raw.replace(a,b,1)
for filename,text in [('proposed-fixture.patch',new),('proposed-fixture-raw.patch',raw)]:
 (OUT/filename).write_text(''.join(difflib.unified_diff(old.splitlines(keepends=True),text.splitlines(keepends=True),fromfile='a/'+name,tofile='b/'+name)))
rows=json.loads((OUT/'source-before.json').read_text())['files'];assert all(hashlib.sha256((ROOT/r['path']).read_bytes()).hexdigest()==r['sha256'] for r in rows)
plan={'status':'PROPOSED_ONLY_NOT_APPLIED','path':name,'base_sha256':hashlib.sha256(old.encode()).hexdigest(),'candidate_sha256':hashlib.sha256(new.encode()).hexdigest(),'patch_sha256':hashlib.sha256((OUT/'proposed-fixture.patch').read_bytes()).hexdigest(),'changed_callbacks':3,'all_test_case_bodies_and_filename_assertions_byte_identical':old.split('async function errorResponse(',1)[1]==new.split('async function errorResponse(',1)[1],'source_current_unchanged':True,'root_review_before_apply':True,'body_comparison':checks}
assert plan['all_test_case_bodies_and_filename_assertions_byte_identical'];(OUT/'proposal.json').write_text(json.dumps(plan,indent=2)+'\n');print(json.dumps({'base_sha':plan['base_sha256'],'candidate_sha':plan['candidate_sha256'],'patch_sha':plan['patch_sha256'],'all_cases_byte_identical':True,'current_source_unchanged':True}))
