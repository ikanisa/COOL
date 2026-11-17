"""Pure metadata-selection guard tests. No Docker, SQL or provider action."""
import copy
import unittest
from types import SimpleNamespace
from scripts.self_hosted.database import migrations
from scripts.self_hosted import qualify_local_stopped_recovery as q


class Current32Boundary(unittest.TestCase):
    def test_observed_oid_json_string_is_canonical_positive_uint32(self):
        self.assertEqual(q.observed_oid('23291'),23291)
        self.assertEqual(q.observed_oid(23291),23291)
        self.assertEqual(q.observed_oid('4294967295'),4294967295)
        for value in ('0','-1','+1','01','1.0','1e3',' 1','1 ','١','4294967296',0,-1,True,1.0,None,{},[]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):q.observed_oid(value)

    def test_upgrade_requires_v3_envelope_with_exact_current_control(self):
        operation=self.args.fence_operation
        value={'contractVersion':3,'found':True,'control':{'mode':'fenced','epoch':8,
            'source_sha256':'c'*64,'operation_id':operation}}
        self.assertIs(q.require_upgrade_ack(value,8,'c'*64,operation),value)
        for mutation in ('flat','missing','notfound','version','mode','epoch','source','operation'):
            with self.subTest(mutation=mutation):
                bad=copy.deepcopy(value)
                if mutation=='flat':bad={'mode':'fenced','epoch':8,'sourceSha256':'c'*64}
                elif mutation=='missing':del bad['control']
                elif mutation=='notfound':bad['found']=False
                elif mutation=='version':bad['contractVersion']=2
                elif mutation=='mode':bad['control']['mode']='open'
                elif mutation=='epoch':bad['control']['epoch']=7
                elif mutation=='source':bad['control']['source_sha256']='f'*64
                else:bad['control']['operation_id']=self.args.admission_id
                with self.assertRaises(ValueError):q.require_upgrade_ack(bad,8,'c'*64,operation)

    def setUp(self):
        self.records=migrations(q.ROOT)
        self.args=SimpleNamespace(profile_sha256='a'*64,source_sha256='b'*64,epoch=7,
            admission_id='00000000-0000-4000-8000-000000000001',fence_operation='00000000-0000-4000-8000-000000000002')
        self.before={'major':17,'database':'postgres','profile':'a'*64,'local_schema':False,
            'journal':[{'version':r['name'],'source_sha256':r['sha256'],'profile_sha256':'a'*64} for r in self.records[:32]],
            'control':{'mode':'quiescing','epoch':7,'source_sha256':'b'*64,'operation_id':self.args.fence_operation},
            'admission':{'admission_id':self.args.admission_id,'epoch':7,'source_sha256':'b'*64,'kind':'http_admin','state':'active','created_at':'2026-11-10T19:18:37.706953+00:00'},
            'boot':'2026-11-11T01:23:45.123456+00:00','scheduler':{'blocking':False}}

    def test_only_actual32_with_genuinely_old_original_is_eligible(self):
        q.require_actual32(self.before,self.records,self.args)
        for change in ('history','tuple','control','profile','schema','time','scheduler'):
            with self.subTest(change=change):
                value=copy.deepcopy(self.before)
                if change=='history':value['journal'][0]['source_sha256']='f'*64
                elif change=='tuple':value['admission']['source_sha256']='f'*64
                elif change=='control':value['control']['mode']='fenced'
                elif change=='profile':value['profile']='f'*64
                elif change=='schema':value['local_schema']=True
                elif change=='time':value['admission']['created_at']=value['boot']
                else:value['scheduler']['blocking']=True
                with self.assertRaises(ValueError):q.require_actual32(value,self.records,self.args)

    def test_metadata_never_selects_provider_bodies_or_prints_auth_rows(self):
        sql=q.metadata_sql(self.args.admission_id)
        self.assertIn('pg_postmaster_start_time()',sql)
        self.assertIn('sha256(convert_to(coalesce(jsonb_agg',sql)
        self.assertNotIn('raw_body',sql);self.assertNotIn('query FROM pg_stat_activity',sql)


if __name__=='__main__':unittest.main()
