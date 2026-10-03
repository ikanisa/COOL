"""Offline strict schema and semantic readback of actual synthetic SQL outputs."""
import hashlib, importlib.metadata, json, pathlib, datetime
import jsonschema
root=pathlib.Path(__file__).resolve().parents[5]
leaf=pathlib.Path(__file__).resolve().parent
fixtures=root/'scripts/tests/fixtures/exception_followup_v2'
load=lambda name:json.loads((fixtures/name).read_text())
schema=load('schema.json');jsonschema.Draft202012Validator.check_schema(schema)
validator=jsonschema.Draft202012Validator(schema)
checks=[]
def check(name,ok):
 assert ok,name
 checks.append({'name':name,'status':'pass'})
def date(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
for path in sorted(fixtures.glob('observed-*.json')):
 if path.name=='observed-assignment-binding.json':continue
 data=json.loads(path.read_text());validator.validate(data)
 check(path.name+' strict actual result shape',True)
 if 'checked_at' in data:
  check(path.name+' exactly60second read TTL',(date(data['sample_valid_until'])-date(data['checked_at'])).total_seconds()==60)
 if 'rows'in data:
  values=[(x['created_at'],x['operator_id'])for x in data['rows']]
  check(path.name+' bounded unique strict paired order',len(values)<=data['limit'] and len({x[1]for x in values})==len(values) and all(values[i]>values[i+1] for i in range(len(values)-1)) and all(date(x[0])<=date(data['checked_at'])for x in values))
  if data['next_cursor']:
   last=data['rows'][-1];check(path.name+' cursor is last visible tuple',data['next_cursor']=={k:last[k]for k in ['created_at','operator_id']})
 if data.get('status')=='recorded':
  receipt=data['receipt'];check(path.name+' actor original receipt binding',receipt['request_id']==data['request_id'] and receipt['request_fingerprint']==data['request_fingerprint'] and date(receipt['recorded_at'])<=date(data['checked_at']))
b=load('observed-assignment-binding.json');r=load('observed-assignment-receipt.json')
text='\n'.join(['collect-exception-workflow-v2',b['request_id'],b['exception_id'],str(b['source_revision']),str(b['workflow_revision']),b['action'],b['assignee_id']or'-',b['due_at']or'-',b['reason_code'],b['expires_at']])
check('ten-line no-trailing-LF exact original input SHA256',len(text.split('\n'))==10 and not text.endswith('\n') and hashlib.sha256(text.encode()).hexdigest()==r['request_fingerprint'])
check('original assignment result is expected workflow revision plus1',r['workflow_revision']==b['workflow_revision']+1 and r['source_revision']==b['source_revision'])
check('original recorded lookup retains exact selected expiry and receipt',load('observed-recorded-lookup.json')['expires_at']==b['expires_at'] and load('observed-recorded-lookup.json')['receipt']==r)
check('foreign lookup discloses no original receipt',load('observed-foreign-lookup.json')['status']=='not_recorded' and load('observed-foreign-lookup.json')['receipt']is None)
check('expired absent lookup uses server checked_at proof',date(load('observed-expired-unrecorded-lookup.json')['checked_at'])>=date(load('observed-expired-unrecorded-lookup.json')['expires_at']))
report={'kind':'offline_schema_semantic_observed_readback','status':'pass','checks':checks,'executed_validator_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'schema_sha256':hashlib.sha256((fixtures/'schema.json').read_bytes()).hexdigest(),'jsonschema_version':importlib.metadata.version('jsonschema'),'hosted_or_database_calls':False}
(leaf/'contract-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'status':'pass','checks':len(checks),'schema_sha256':report['schema_sha256']}))
