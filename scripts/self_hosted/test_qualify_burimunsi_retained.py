"""Host-only control and identity tests. No Docker, SQL, sockets or providers."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import subprocess
import tempfile
from scripts.self_hosted import qualify_burimunsi_retained as q
from scripts.self_hosted.database import migrations,sha
from scripts.supabase.deployment_profile import canonical_profile

ROOT=Path(__file__).resolve().parents[2]
OPERATIONS={name:'00000000-0000-4000-8000-'+f'{i:012d}' for i,name in enumerate(('initialize','quiesce','release'),1)}
PROFILE={'format':'collect.deployment.v1','id':'collect-retained-rehearsal','mode':'self_hosted','environment':'qualification',
 'supabase_origin':'https://supabase.example.invalid','member_api_origin':'https://api.example.invalid',
 'admin_origin':'https://admin.example.invalid','public_origin':'https://collect.example.invalid','google_callback_origin':'https://admin.example.invalid'}

class Installer:
    def __init__(self,records,*,bad_drain=False,changed_prefix=False,lost_apply=False,changed_32=False,lost_second=False,changed_33=False,lost_third=False,changed_34=False,lost_fourth=False,allow_uninitialized=False):
        self.records=records;self.calls=[];self.apply_calls=[];self.rows={r['name']:{'version':r['name'],'source_sha256':r['sha256'],'profile_sha256':sha(canonical_profile(PROFILE).encode()),'operation_id':str(i)} for i,r in enumerate(records[:31])}
        self.bad_drain=bad_drain;self.changed_prefix=changed_prefix;self.lost_apply=lost_apply;self.changed_32=changed_32;self.lost_second=lost_second
        self.changed_33=changed_33;self.lost_third=lost_third;self.changed_34=changed_34;self.lost_fourth=lost_fourth;self.allow_uninitialized=allow_uninitialized
        self.mode=None;self.operation=None;self.epoch=0
        self.op=SimpleNamespace(meta={'source_sha256':'a'*64,'profile_sha256':sha(canonical_profile(PROFILE).encode())},profile=PROFILE,sql=self.sql)
    def applied(self):return copy.deepcopy(self.rows)
    def sql(self,text):
        self.calls.append(text)
        if text.startswith('SELECT to_jsonb(EXISTS'):return json.dumps(self.mode is not None).encode()
        for name,mode,operation,epoch in [('collect_fence_initialize','open','initialize',1),
          ('collect_fence_begin_quiesce','quiescing','quiesce',1),('collect_fence_drain','quiescing' if self.bad_drain else 'fenced','quiesce',1),
          ('collect_fence_release','open','release',2)]:
            if 'private.'+name+'(' in text:
                self.mode=mode;self.operation=OPERATIONS[operation];self.epoch=epoch;break
        if 'collect_bind_deployment(' in text:return b't\n'
        return json.dumps({'mode':self.mode,'epoch':self.epoch,'operationId':self.operation,'sourceSha256':'a'*64,
            'activeAdmissions':0,'unresolvedAdmissions':0,'applicationFenceComplete':self.mode=='fenced'}).encode()
    def apply_records(self,records):
        self.apply_calls.append(copy.deepcopy(records))
        if self.mode!='fenced' and not(self.allow_uninitialized and self.mode is None and records[0]['name']!=q.ADOPTION_MIGRATION):raise AssertionError('Adoption requires FENCED; earlier DDL must not reach an open fixture')
        self.calls.append('APPLY:'+records[0]['name'])
        if records!=[self.records[30+len(self.apply_calls)]]:raise AssertionError('Only reviewed32 through35 may be applied')
        if self.lost_apply or(self.lost_second and len(self.apply_calls)==2) or(self.lost_third and len(self.apply_calls)==3) or(self.lost_fourth and len(self.apply_calls)==4):raise RuntimeError('synthetic unconfirmed apply')
        for row in records:self.rows[row['name']]={'version':row['name'],'source_sha256':row['sha256'],'profile_sha256':self.op.meta['profile_sha256'],'operation_id':'new'}
        if self.changed_prefix:self.rows[next(iter(self.rows))]['source_sha256']='f'*64
        if self.changed_32 and len(self.apply_calls)==2:self.rows[self.records[31]['name']]['operation_id']='tampered'
        if self.changed_33 and len(self.apply_calls)==3:self.rows[self.records[32]['name']]['operation_id']='tampered'
        if self.changed_34 and len(self.apply_calls)==4:self.rows[self.records[33]['name']]['operation_id']='tampered'
        return [r['name'] for r in records]

class RetainedPhonePinQualification(unittest.TestCase):
    def setUp(self):self.records=migrations(ROOT)
    def test_failed_compiler_preserves_private_diagnostics_and_original_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory);result=subprocess.CompletedProcess(['node','fixture'],1,b'',b'synthetic compiler failure')
            with patch.object(q.subprocess,'run',return_value=result) as run:
                with self.assertRaises(subprocess.CalledProcessError):q.compile_fixture_process('node',Path('fixture'),output,'scope-setup')
            self.assertEqual((output/'scope-setup-compiler.private.stderr').read_bytes(),b'synthetic compiler failure')
            self.assertEqual((output/'scope-setup-compiler.private.stderr').stat().st_mode & 0o777,0o600)
            self.assertEqual(run.call_count,1)

    def test_successful_compiler_diagnostics_are_kept_without_overwriting_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory);result=subprocess.CompletedProcess(['node','fixture'],0,b'{"ok":true}',b'')
            with patch.object(q.subprocess,'run',return_value=result):
                self.assertIs(q.compile_fixture_process('node',Path('fixture'),output,'gateway'),result)
                with self.assertRaises(FileExistsError):q.compile_fixture_process('node',Path('fixture'),output,'gateway')
            self.assertEqual((output/'gateway-compiler.private.stdout').read_bytes(),b'{"ok":true}')

    def test_exact35_chain_inserts_local33_and_preserves_old_pending_sql_names(self):
        baseline,targets=q.reviewed_chain(self.records)
        self.assertEqual(len(baseline),31);self.assertEqual([r['name'] for r in targets],[q.PIN_MIGRATION,q.LOCAL_STOPPED_MIGRATION,q.HANDOFF_MIGRATION,q.ADOPTION_MIGRATION])
        for changed in (self.records[:-1],self.records+[self.records[-1]],self.records[:-2]+list(reversed(self.records[-2:]))):
            with self.subTest(length=len(changed)):
                with self.assertRaises(ValueError):q.reviewed_chain(changed)
    def test_live_or_partially_initialized_source_cannot_be_a_clean_baseline(self):
        installer=Installer(self.records);journal=list(installer.applied().values())
        q.require_clean_baseline(q.clean_state(),journal,self.records)
        for key,value in [('auth_users',1),('native_accounts',1),('business_users',1),('collections',1),('ledger_entries',1),
                          ('receiving_accounts',1),('fence_initialized',True),('deployment_bound',True),('native_pin_schema',True),('native_local_stopped_schema',True),('native_handoff_schema',True),('native_adoption_schema',True),('migrations',32)]:
            with self.subTest(field=key):
                with self.assertRaises(ValueError):q.require_clean_baseline({**q.clean_state(),key:value},journal,self.records)
        with self.assertRaises(ValueError):q.require_clean_baseline(q.clean_state(),list(reversed(journal)),self.records)
    def test_only32_through35_apply_fenced_and_predecessor_journals_survive(self):
        installer=Installer(self.records);journal=list(installer.applied().values())
        result=q.upgrade_disposable_baseline(installer,journal,OPERATIONS)
        self.assertEqual(installer.apply_calls,[[self.records[31]],[self.records[32]],[self.records[33]],[self.records[34]]])
        self.assertEqual(list(installer.applied().values())[:31],journal)
        self.assertEqual(result['preserved_journal_prefix'],34)
        self.assertEqual(list(installer.applied().values())[:32],result['journal32'])
        self.assertEqual(list(installer.applied().values())[:33],result['journal33'])
        self.assertEqual(list(installer.applied().values())[:34],result['journal34'])
        self.assertEqual(result['fenced']['mode'],'fenced');self.assertEqual(result['released']['epoch'],2)
        self.assertFalse(result['production_acceptance']);self.assertFalse(result['live_source_migrated'])
        self.assertEqual(sum('collect_fence_release(' in text for text in installer.calls),1)
    def test_uninitialized32_to34_then_fenced35_preserves_original_operations(self):
        installer=Installer(self.records,allow_uninitialized=True);journal=list(installer.applied().values())
        result=q.upgrade_disposable_baseline(installer,journal,OPERATIONS,install_state='uninitialized')
        self.assertEqual(result['installation_state'],'uninitialized')
        self.assertEqual(len(installer.apply_calls),4)
        applies=[i for i,text in enumerate(installer.calls) if text.startswith('APPLY:')]
        first_initialize=next(i for i,text in enumerate(installer.calls) if 'collect_fence_initialize(' in text)
        drain=next(i for i,text in enumerate(installer.calls) if 'collect_fence_drain(' in text)
        self.assertLess(applies[2],first_initialize)
        self.assertLess(first_initialize,drain)
        self.assertLess(drain,applies[3])
        for name in ('initialize','begin_quiesce','drain','release'):
            self.assertEqual(sum('collect_fence_'+name+'(' in text for text in installer.calls),1)
        self.assertEqual(result['released']['mode'],'open')
        self.assertEqual(q.selected_fixtures('install-only'),())

    def test_unconfirmed_uninitialized_path_fence_cannot_apply35_or_release(self):
        installer=Installer(self.records,allow_uninitialized=True,bad_drain=True)
        with self.assertRaises(ValueError):q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS,install_state='uninitialized')
        self.assertEqual(len(installer.apply_calls),3)
        self.assertFalse(any(text=='APPLY:'+q.ADOPTION_MIGRATION for text in installer.calls))
        self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))

    def test35_cannot_change_any34_journal_row_or_release_unknown_commit(self):
        for options in ({'changed_34':True},{'lost_fourth':True}):
            with self.subTest(options=options):
                installer=Installer(self.records,**options)
                with self.assertRaises((ValueError,RuntimeError)):
                    q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS)
                self.assertEqual(len(installer.apply_calls),4)
                self.assertEqual(installer.mode,'fenced')
                self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))

    def test_unconfirmed_drain_never_applies_or_releases(self):
        installer=Installer(self.records,bad_drain=True)
        with self.assertRaises(ValueError):q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS)
        self.assertEqual(installer.apply_calls,[])
        self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))
    def test_changed_journal_or_unknown_apply_outcome_stays_closed_without_retry(self):
        for options in ({'changed_prefix':True},{'lost_apply':True}):
            with self.subTest(options=options):
                installer=Installer(self.records,**options)
                with self.assertRaises((ValueError,RuntimeError)):q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS)
                self.assertEqual(len(installer.apply_calls),1)
                self.assertEqual(installer.mode,'fenced')
                self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))
    def test33_cannot_change_any32_journal_row_or_release_unknown_commit(self):
        for options in ({'changed_32':True},{'lost_second':True}):
            with self.subTest(options=options):
                installer=Installer(self.records,**options)
                with self.assertRaises((ValueError,RuntimeError)):
                    q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS)
                self.assertEqual(len(installer.apply_calls),2)
                self.assertEqual(installer.mode,'fenced')
                self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))

    def test_profile_and_copied_journal_drift_fail_before_initialization(self):
        for problem in ('profile','journal','operation'):
            with self.subTest(problem=problem):
                installer=Installer(self.records);journal=list(installer.applied().values());operations=dict(OPERATIONS)
                if problem=='profile':installer.op.meta['profile_sha256']='f'*64
                elif problem=='journal':journal[0]['source_sha256']='f'*64
                else:operations['release']=operations['initialize']
                with self.assertRaises(ValueError):q.upgrade_disposable_baseline(installer,journal,operations)
                self.assertEqual(installer.calls,[]);self.assertEqual(installer.apply_calls,[])
    def test34_cannot_change_any33_journal_row_or_release_unknown_commit(self):
        for options in ({'changed_33':True},{'lost_third':True}):
            with self.subTest(options=options):
                installer=Installer(self.records,**options)
                with self.assertRaises((ValueError,RuntimeError)):
                    q.upgrade_disposable_baseline(installer,list(installer.applied().values()),OPERATIONS)
                self.assertEqual(len(installer.apply_calls),3)
                self.assertEqual(installer.mode,'fenced')
                self.assertFalse(any('collect_fence_release(' in text for text in installer.calls))

    def test_all16_fixtures_preserve_old14_and_real_readonly_work(self):
        for contract in ('all','phone-pin','phone-pin-readonly','gateway-handoff','gateway-handoff-readonly'):
            selected=q.selected_fixtures(contract)
            expected='canonical-adoption-contract.sql' if contract=='all' else ('gateway-handoff-readonly-contract.sql' if contract.startswith('gateway-handoff') else 'phone-pin-readonly-contract.sql')
            self.assertEqual(selected[-1],expected)
            self.assertEqual(selected[:3],q.FIXTURES[:3])
        self.assertEqual(len(q.FIXTURES),16)
        self.assertEqual(q.FIXTURES[-3],'gateway-handoff-readonly-contract.sql')
        self.assertEqual(q.FIXTURES[-2: ],('platform-public-group-contract.sql','canonical-adoption-contract.sql'))
        for name in ('phone-pin-readonly-contract.sql','gateway-handoff-readonly-contract.sql'):
            self.assertEqual(q.COMPILED_CONTRACTS[name][1],('native_pair_inputs',) if name.startswith('gateway-handoff') else ())
            text=(ROOT/'supabase/tests/burimunsi'/name).read_text()
            for parameter in ('ADMISSION_ID','ADMISSION_EPOCH','ADMISSION_SOURCE'):self.assertIn('__'+parameter+'__',text)
        for name in ('phone-pin-readonly-contract.sql','gateway-handoff-readonly-contract.sql'):
            readonly=(ROOT/'supabase/tests/burimunsi'/name).read_text()
            self.assertIn('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;',readonly)
            self.assertLess(readonly.index('COMMIT;'),readonly.index('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'))
    def test_public_compiler_format_and_field_use_actual_frozen_contract(self):
        self.assertEqual(q.fixture_format('platform-public-group'),'collect.platform-sponsored.sql-fixture.v1')
        self.assertEqual(q.COMPILED_CONTRACTS['platform-public-group-contract.sql'],('platform-public-group',('setup_inputs',)))
        self.assertEqual(q.fixture_format('gateway-handoff-readonly'),q.fixture_format('gateway-handoff'))
        self.assertEqual(q.fixture_format('canonical-adoption'),'collect.burimunsi.canonical-adoption-sql-fixture.v1')
        self.assertIn('__PLATFORM_PUBLIC_INPUTS__',(ROOT/'supabase/tests/burimunsi/platform-public-group-contract.sql').read_text())

    def test_allocate_receipt_requires_real_one_post_replay_dedup_and_cleanup_evidence(self):
        value={'format':'collect.burimunsi.adopted-native-allocation.actual-pg.v1','status':'pass',
               'original_native_allocate_executed':True,'native_session_revalidated':True,
               'exact_replay_same_result':True,'second_request_did_not_repost':True,
               'canonical_duplicate_did_not_repost':True,'first_scope_preserved':True,
               'owned_psql_cleanup_confirmed':True,'production_acceptance':False,'gotrue_exercised':False,
               'provider_calls':0,'native_work_close':{'applicationWorkFinished':True},'counts':{'payments':1,'ledger':1,'links':1,'snapshots':1,'receipts':1},
               'canonical_counts':{'facts':1,'accepted':1,'duplicates':1,'scopes':1}}
        self.assertIs(q.require_allocation_result(value),value)
        for key,bad in [('original_native_allocate_executed',False),('canonical_duplicate_did_not_repost',False),
                        ('first_scope_preserved',False),('owned_psql_cleanup_confirmed',False),
                        ('native_work_close',{'applicationWorkFinished':False}),
                        ('counts',{**value['counts'],'ledger':0}),('counts',{**value['counts'],'ledger':2}),
                        ('canonical_counts',{**value['canonical_counts'],'facts':2}),('provider_calls',1),
                        ('production_acceptance',True),('gotrue_exercised',True)]:
            with self.subTest(field=key,bad=bad):
                with self.assertRaises(ValueError):q.require_allocation_result({**value,key:bad})

    def test_wrong_fence_identity_epoch_source_or_unresolved_work_never_counts_as_fenced(self):
        state={'mode':'fenced','epoch':1,'operationId':OPERATIONS['quiesce'],'sourceSha256':'a'*64,
               'activeAdmissions':0,'unresolvedAdmissions':0,'applicationFenceComplete':True}
        q.require_control(state,'fenced',1,OPERATIONS['quiesce'],'a'*64)
        for key,value in [('mode','open'),('epoch',2),('operationId',OPERATIONS['release']),('sourceSha256','b'*64),
                          ('activeAdmissions',1),('unresolvedAdmissions',1),('applicationFenceComplete',False)]:
            with self.subTest(field=key):
                with self.assertRaises(ValueError):q.require_control({**state,key:value},'fenced',1,OPERATIONS['quiesce'],'a'*64)

if __name__=='__main__':unittest.main()
