"""Execute the actual controller main input prefix, stopping before output/network."""
import ast,hashlib,importlib.util,json,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
command=json.loads((HERE/'commands.json').read_bytes())['argv']
source=HERE/'acquire_binaries.py';tree=ast.parse(source.read_text());actual_main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main');prefix=[]
for statement in actual_main.body:
 if isinstance(statement,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='output' for t in statement.targets):break
 prefix.append(statement)
assert prefix and len(prefix)<len(actual_main.body)
prefix.append(ast.parse("return {'input_rows':len(fences['inputs']), 'plan_counts':plan['counts'], 'actual_selected_modules':len(selected), 'Python_bytes':fences['Python_bytes'], 'graph_errors':graph['errors']}\n").body[0]);function=ast.FunctionDef(name='actual_main_input_preflight',args=actual_main.args,body=prefix,decorator_list=[]);module=ast.fix_missing_locations(ast.Module(body=[function],type_ignores=[]))
spec=importlib.util.spec_from_file_location('actual_private_binary_controller',source);controller=importlib.util.module_from_spec(spec);spec.loader.exec_module(controller)
def refused(*args,**kwargs):raise AssertionError('Network/child acquisition is outside preflight')
controller.subprocess.Popen=refused;exec(compile(module,str(source)+'#actual-main-input-prefix','exec'),controller.__dict__);before_argv=sys.argv;started=time.monotonic()
output=Path(command[command.index('--output')+1]);assert not output.exists();sys.argv=[str(source),*command[command.index('--plan-sha256'):]]
try:result=controller.actual_main_input_preflight()
finally:sys.argv=before_argv
assert not output.exists();assert result=={'input_rows':211,'plan_counts':{'unique_JARs':67,'module_declared':7,'Maven_fallback':60,'selected_modules':69,'excluded_duplicate_or_POM_components':2},'actual_selected_modules':69,'Python_bytes':18041888,'graph_errors':[]}
readback={'status':'PASS_ACTUAL_MAIN_INPUT_PREFIX_ONLY','actual_seconds':time.monotonic()-started,'actual_controller_sha256':sha(source.read_bytes()),'source_fences_sha256':sha((HERE/'source-fences.json').read_bytes()),'executed_actual_main_statements':len(prefix)-1,'first_output_assignment_and_all_following_statements_not_executed':True,'all211_actual_source_rows_and_real_runtime_bytes_qualified':True,'all67_actual_plan_variant_guards_qualified':True,'actual_current_selected_module_count':69,'output_absent_before_and_after':True,'network_or_binary_acquisition_calls':0,'root_original_failure_not_relabelled':True,'unaffected11fixture_suite_not_rerun':True,'result':result}
(HERE/'main-inputs-preflight-readback.json').write_text(json.dumps(readback,indent=2,sort_keys=True)+'\n');print(json.dumps(readback,indent=2))
