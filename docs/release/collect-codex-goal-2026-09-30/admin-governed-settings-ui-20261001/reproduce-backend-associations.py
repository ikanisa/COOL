#!/usr/bin/env python3
"""Read-only reproduce the seven sealed backend AST associations."""
from pathlib import Path
import ast,hashlib,json
P=Path('.cache/governed-settings-request-20261001');R='scripts/tests/governed_settings_requests_uat.py';S=P/'accepted-proof-current1'
def fn(path,name):return next(n for n in ast.parse(path.read_text()).body if isinstance(n,ast.FunctionDef)and n.name==name)
def dump(nodes):return ast.dump(ast.Module(body=nodes,type_ignores=[]),include_attributes=False)
def bind(name,x,y):
 assert dump(x)==dump(y),name
 return dict(name=name,status='pass',normalized_ast_sha256=hashlib.sha256(dump(x).encode()).hexdigest(),nodes=len(x))
old=fn(P/'attempt6/executed-inputs'/R,'main');new=fn(P/R,'main');o=next(n for n in old.body if isinstance(n,ast.Try));n=next(n for n in new.body if isinstance(n,ast.Try));a=next(i for i,x in enumerate(o.body)if isinstance(x,ast.For)and ast.unparse(x.target)=='k'and ast.unparse(x.iter)=='families');z=next(i for i,x in enumerate(n.body)if isinstance(x,ast.If)and ast.unparse(x.test)=="a.scope == 'full'");end=next(i for i,x in enumerate(o.body)if isinstance(x,ast.Expr)and isinstance(x.value,ast.Call)and ast.unparse(x.value.func)=='run_extended');full=next(x for x in n.body if isinstance(x,ast.If)and ast.unparse(x.test)=="a.scope == 'full'")
out=[bind('attempt6 all25 family loop and entire original no-op/permission/auth negative body',o.body[a:end],full.body)]
cur=fn(P/R,'run_extended');old7=fn(P/'affected-attempt7/executed-inputs'/R,'run_extended');old8=fn(P/'affected-tail-attempt8/executed-inputs'/R,'run_extended');core=next(x for x in cur.body if isinstance(x,ast.If)and ast.unparse(x.test)=="c['a'].scope != 'extended-tail'")
start7=next(i for i,x in enumerate(old7.body)if isinstance(x,ast.For)and isinstance(x.target,ast.Tuple)and ast.unparse(x.target)=='(label, kwargs, reason)');expiry7=next(i for i,x in enumerate(old7.body)if isinstance(x,ast.Expr)and isinstance(x.value,ast.Call)and ast.unparse(x.value.func)=='sql'and '1.2 seconds'in ast.unparse(x)and 'email_approvals'in ast.unparse(x));out.append(bind('attempt7 exact deadline/concurrency/insertion fence body before original failed expiry fixture',old7.body[start7:expiry7],core.body))
def tail(ns):
 a=next(i for i,x in enumerate(ns)if isinstance(x,ast.Expr)and isinstance(x.value,ast.Call)and ast.unparse(x.value.func)=='sql'and '1.2 seconds'in ast.unparse(x)and 'email_approvals'in ast.unparse(x));b=next(i for i,x in enumerate(ns)if isinstance(x,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='plan'for t in x.targets));return ns[a:b]
out.append(bind('attempt8 actual approval expiry/publication/identity/catalog/history body before diagnostic parse',tail(old8.body),tail(cur.body)))
out.append(bind('attempt6 entire fixture/install/get/make/fingerprint/lookup common setup',o.body[:a],n.body[:z]))
keep=lambda ns:[x for x in ns if not isinstance(x,ast.FunctionDef)and not isinstance(x,ast.If)]
out.append(bind('attempt6 all module import/global DTO constants and quote/hash/time helpers',keep(ast.parse((P/'attempt6/executed-inputs'/R).read_text()).body),keep(ast.parse((P/R).read_text()).body)))
core_index=next(i for i,x in enumerate(cur.body)if isinstance(x,ast.If)and ast.unparse(x.test)=="c['a'].scope != 'extended-tail'");out.append(bind('attempt7 all common session/blocking/snapshot race helpers',old7.body[:start7],cur.body[1:core_index]))
old9=fn(P/'final-only-attempt9/executed-inputs'/R,'run_final');new9=fn(P/R,'run_new_boundary');start9=next(i for i,x in enumerate(old9.body)if isinstance(x,ast.Expr)and isinstance(x.value,ast.Call)and ast.unparse(x.value.func)=='case'and ast.literal_eval(x.value.args[0])=='changed original deadline cannot reuse UUID');out.append(bind('final9 new exact original-input/create/sensitive boundary body now included in default full scope',old9.body[start9:],new9.body[2:]))
assert out==json.loads((S/'runner-body-equivalence.json').read_text())
print(json.dumps({'status':'pass','equivalences':len(out),'node_counts':[x['nodes']for x in out]}))
