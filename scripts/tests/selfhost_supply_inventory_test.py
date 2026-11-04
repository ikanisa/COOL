"""Offline self-host lock declarations, not installed or deployed packages."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.supply_chain import inventory, source_sbom, validate_source_sbom

SRI='sha512-'+base64.b64encode(bytes(range(64))).decode()
HEX='a'*64

def deno_lock():
    return {'version':'5','specifiers':{'npm:example@1.2.3':'1.2.3','jsr:@std/assert@1.0.14':'1.0.14'},
        'npm':{'example@1.2.3':{'integrity':SRI}},'jsr':{'@std/assert@1.0.14':{'integrity':HEX,'dependencies':['jsr:@std/internal']}}}

def tooling():
    manifest={'name':'@collect/tooling','version':'0.1.0','dependencies':{'pg':'8.16.3'},'devDependencies':{'deno':'2.9.6'}}
    entries={'':{**manifest},'node_modules/pg':{'version':'8.16.3','resolved':'https://registry.example.invalid/pg','integrity':SRI},
        'node_modules/deno':{'version':'2.9.6','resolved':'https://registry.example.invalid/deno','integrity':SRI,'dev':True},
        'node_modules/deno/node_modules/pg':{'version':'8.16.3','resolved':'https://registry.example.invalid/pg','integrity':SRI,'dev':True,'optional':True,'os':['linux'],'cpu':['arm64']}}
    return manifest,{'name':manifest['name'],'version':manifest['version'],'lockfileVersion':3,'packages':entries}

def images():
    tag='registry.example.invalid/collect:1.2.3';digest='sha256:'+HEX
    platforms=[{'os':'windows','architecture':'amd64','digest':'sha256:'+'b'*64,'os.version':'one'},
        {'os':'windows','architecture':'amd64','digest':'sha256:'+'c'*64,'os.version':'two'}]
    return {'format':'collect.selfhost.images.v1','services':{'api':{'tag':tag,'reference':tag+'@'+digest,'manifest_digest':digest,'platforms':platforms}}}

class SelfhostSupplyInventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()
        self.patcher=patch.object(inventory,'ROOT',self.root);self.patcher.start();self.addCleanup(self.patcher.stop)
        manifest,lock=tooling();self.write('supabase/functions/deno.lock',deno_lock());self.write('scripts/supabase/package.json',manifest)
        self.write('scripts/supabase/package-lock.json',lock);self.write('deploy/self-hosted/images.lock.json',images())

    def write(self,path,data):
        target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(data))

    def test_deno_lock_provenance_does_not_claim_jsr_archive_hash(self):
        sources={};rows,summary=inventory.deno_lock_packages(sources)
        self.assertEqual((summary['npm_entries'],summary['jsr_entries']),(1,1))
        jsr=next(row for row in rows if row['ecosystem']=='jsr')
        self.assertIsNone(jsr['integrity']);self.assertEqual(jsr['lock_metadata_integrity'],HEX)
        self.assertEqual(jsr['lock_metadata_dependencies'],['jsr:@std/internal'])
        self.assertEqual(next(row['integrity'] for row in rows if row['ecosystem']=='npm'),SRI)
        self.assertEqual(set(sources),{'supabase/functions/deno.lock'})

    def test_deno_rejects_malformed_or_unresolved_locks(self):
        for mutation in ('version','npm_hash','jsr_hash','identity','missing_specifier','mismatched_exact_specifier','invalid_selector','dependency_type'):
            with self.subTest(mutation=mutation):
                lock=deno_lock()
                if mutation=='version':lock['version']='4'
                if mutation=='npm_hash':lock['npm']['example@1.2.3']['integrity']='sha512-bad'
                if mutation=='jsr_hash':lock['jsr']['@std/assert@1.0.14']['integrity']='g'*64
                if mutation=='identity':lock['npm']['example@^1']=lock['npm'].pop('example@1.2.3')
                if mutation=='missing_specifier':lock['specifiers']['npm:missing@1.2.3']='1.2.3'
                if mutation=='mismatched_exact_specifier':lock['specifiers']['npm:example@1.2.4']='1.2.3'
                if mutation=='invalid_selector':lock['specifiers']['npm:example@not-a-range']='1.2.3'
                if mutation=='dependency_type':lock['jsr']['@std/assert@1.0.14']['dependencies']=[None]
                self.write('supabase/functions/deno.lock',lock)
                with self.assertRaises(ValueError):inventory.deno_lock_packages({})

    def test_deno_range_satisfaction_is_explicitly_not_claimed(self):
        lock=deno_lock();lock['specifiers']['npm:example@^9.0.0']='1.2.3';self.write('supabase/functions/deno.lock',lock)
        _,summary=inventory.deno_lock_packages({});self.assertEqual(summary['range_satisfaction'],'not evaluated')

    def test_duplicate_json_keys_are_refused(self):
        (self.root/'supabase/functions/deno.lock').write_text('{"version":"5","version":"5"}')
        with self.assertRaisesRegex(ValueError,'Duplicate JSON key'):inventory.deno_lock_packages({})

    def test_tooling_root_direct_scope_and_nested_optional_metadata_are_distinct(self):
        rows,summary=inventory.supabase_tool_packages({});self.assertEqual(summary['locked_entries'],3)
        direct=next(row for row in rows if row['lock_path']=='node_modules/pg')
        nested=next(row for row in rows if row['lock_path']=='node_modules/deno/node_modules/pg')
        self.assertEqual(direct['relationship'],'tooling direct dependencies');self.assertFalse(direct['development'])
        self.assertEqual(nested['relationship'],'tooling transitive or optional');self.assertTrue(nested['development']);self.assertTrue(nested['optional'])
        self.assertEqual(nested['platform_metadata'],{'os':['linux'],'cpu':['arm64']})

    def test_tooling_rejects_bad_pin_scope_and_integrity(self):
        for mutation in ('version','integrity','direct_scope','missing','declaration','root_name','root_version','lock_name','path','flag','platform'):
            with self.subTest(mutation=mutation):
                manifest,lock=tooling();entries=lock['packages']
                if mutation=='version':entries['node_modules/pg']['version']='8.16'
                if mutation=='integrity':entries['node_modules/pg']['integrity']='sha256-bad'
                if mutation=='direct_scope':entries['node_modules/deno']['dev']=False
                if mutation=='missing':del entries['node_modules/pg']
                if mutation=='declaration':manifest['dependencies']['pg']='8.16.4'
                if mutation=='root_name':entries['']['name']='@collect/other'
                if mutation=='root_version':entries['']['version']='0.2.0'
                if mutation=='lock_name':lock['name']='@collect/other'
                if mutation=='path':entries['../escape']=entries.pop('node_modules/pg')
                if mutation=='flag':entries['node_modules/pg']['optional']='false'
                if mutation=='platform':entries['node_modules/pg']['os']='linux'
                self.write('scripts/supabase/package.json',manifest);self.write('scripts/supabase/package-lock.json',lock)
                with self.assertRaises(ValueError):inventory.supabase_tool_packages({})

    def test_image_manifest_and_each_platform_are_declarations_not_artifact_hashes(self):
        rows,summary=inventory.selfhost_image_packages({});self.assertEqual((summary['services'],summary['platform_descriptors']),(1,2))
        self.assertIsNone(rows[0]['integrity']);self.assertEqual(rows[0]['declared_manifest_digest'],'sha256:'+HEX)
        self.assertEqual(len(rows[0]['declared_platforms']),2);self.assertEqual(rows[0]['declared_platforms'][0]['os.version'],'one')

    def test_image_lock_refuses_ambiguous_or_malformed_pins(self):
        for mutation in ('reference','manifest','duplicate','missing_platform','platform_digest','unknown_field'):
            with self.subTest(mutation=mutation):
                lock=images();entry=lock['services']['api']
                if mutation=='reference':entry['reference']='foreign@'+entry['manifest_digest']
                if mutation=='manifest':entry['manifest_digest']='sha256:bad'
                if mutation=='duplicate':entry['platforms'].append(dict(entry['platforms'][0]))
                if mutation=='missing_platform':entry['platforms']=[]
                if mutation=='platform_digest':entry['platforms'][0]['digest']='sha256:bad'
                if mutation=='unknown_field':entry['platforms'][0]['unreviewed']=['x']
                self.write('deploy/self-hosted/images.lock.json',lock)
                with self.assertRaises(ValueError):inventory.selfhost_image_packages({})

    def test_sbom_preserves_distinct_tool_paths_and_lock_only_provenance(self):
        sources={};deno,_=inventory.deno_lock_packages(sources);tool,_=inventory.supabase_tool_packages(sources);oci,_=inventory.selfhost_image_packages(sources)
        document={'source_sha256':sources,'assets':[],'packages':deno+tool+oci,'checks':{'dart':{'pubspec_version':'1.2.3'}},'coverage':{'included':[],'excluded':[]}}
        path=self.root/'inventory.json';path.write_text(json.dumps(document))
        with patch.object(source_sbom,'ROOT',self.root):result=source_sbom.build(path)
        self.assertEqual(validate_source_sbom.validate_bytes(json.dumps(result).encode()),[])
        pg=[item for item in result['components'] if item['name']=='pg'];self.assertEqual(len(pg),2)
        paths={next(p['value'] for p in item['properties'] if p['name']=='collect:lock_path') for item in pg}
        self.assertEqual(paths,{'node_modules/pg','node_modules/deno/node_modules/pg'})
        jsr=next(item for item in result['components'] if item['group']=='jsr');self.assertNotIn('hashes',jsr)
        self.assertEqual(next(p['value'] for p in jsr['properties'] if p['name']=='collect:lock_metadata_integrity'),HEX)
        image=next(item for item in result['components'] if item['group']=='oci');self.assertNotIn('hashes',image)
        image_props={p['name']:p['value'] for p in image['properties']};self.assertEqual(image_props['collect:declared_manifest_digest'],'sha256:'+HEX)
        self.assertEqual(len(json.loads(image_props['collect:declared_platforms'])),2)

if __name__=='__main__':unittest.main()
