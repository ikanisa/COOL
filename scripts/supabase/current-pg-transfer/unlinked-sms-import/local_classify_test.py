import copy
import importlib.util
import json
import unittest
from pathlib import Path

path=Path(__file__).with_name('local_classify.py')
spec=importlib.util.spec_from_file_location('local_classify',path)
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)

def synthetic():
 identity={'tag':'identity','database':'postgres','major':17,'socket':True,'session':'postgres','role':'postgres',
  'replication':'origin','system_identifier':'123456789','postmaster_started':'synthetic-start','backend_pid':123,'database_oid':5}
 scope={'receipts':2,'linked':1,'unlinked':1,'link_unknown':0,'multiple_paths':0}
 u={name:0 for name in mod.UNLINKED}
 for name in ('allocation_not_applicable','state_completed','phase_finished','event_failed_pending_other_unknown',
  'outcome_not_successful_or_null','amount_null','currency_null','currency_scale_null','transaction_wallet_null',
  'posting_facts_sql_null','posting_facts_incomplete'):u[name]=1
 obs={'format':'collect.native-unlinked-classification.v1','observed_at_utc':'2026-11-14T12:00:00.000000Z','scope':scope,'unlinked':u,
  'visibility':{'active_rls_filtering':False,'full_table_select_checked':True,'inherited_tables_refused':True,'required_columns_checked':True},
  'source_frozen':False,'complete_graph_verified':False,'provider_or_object_verified':False,'write_authorized':False}
 return identity,obs

def encoded(first,obs,last=None):
 return ('\n'.join(json.dumps(x) for x in (first,obs,last if last is not None else first))+'\n').encode()

class OutputGuardTests(unittest.TestCase):
 def test_accepts_only_aggregate_counts_and_matching_identity(self):
  identity,obs=synthetic();self.assertEqual(mod.validate_output(encoded(identity,obs)),obs)

 def test_rejects_potential_row_or_identifier_leak(self):
  identity,obs=synthetic();obs['unlinked']['source_id']='SYNTHETIC-CANARY'
  with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs))

 def test_rejects_changed_database_or_backend_identity(self):
  identity,obs=synthetic();after=copy.deepcopy(identity);after['backend_pid']+=1
  with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs,after))

 def test_rejects_remote_or_wrong_session(self):
  identity,obs=synthetic();identity['socket']=False
  with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs))

 def test_rejects_hidden_rows_unsupported_readiness_and_bad_counts(self):
  for mutate in (lambda x:x['visibility'].__setitem__('active_rls_filtering',True),
   lambda x:x.__setitem__('source_frozen',True),lambda x:x['scope'].__setitem__('unlinked',2),
   lambda x:x['unlinked'].__setitem__('amount_null',True),lambda x:x['unlinked'].__setitem__('event_incoming',1)):
   identity,obs=synthetic();mutate(obs)
   with self.subTest(mutate=mutate):
    with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs))

 def test_rejects_missing_job_also_counted_as_existing_null_facts(self):
  identity,obs=synthetic();obs['unlinked']['job_missing']=1;obs['unlinked']['graph_mismatch_or_unknown']=1
  with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs))

 def test_rejects_extra_output_and_oversized_response(self):
  identity,obs=synthetic()
  with self.assertRaises(ValueError):mod.validate_output(encoded(identity,obs)+b'{}\n')
  with self.assertRaises(ValueError):mod.validate_output(b'x'*65537)

if __name__=='__main__':unittest.main()
