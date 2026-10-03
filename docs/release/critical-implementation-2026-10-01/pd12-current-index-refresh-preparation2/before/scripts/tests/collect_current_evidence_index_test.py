#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC=importlib.util.spec_from_file_location('current_index',Path(__file__).resolve().parents[1]/'audits'/'collect_current_evidence_index.py')
M=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(M)

class CurrentIndexTests(unittest.TestCase):
    def fixture(self,root):
        (root/'lib').mkdir();(root/'lib/one.dart').write_bytes(b'void main() {}\n')
        source=b'void main() {}\n';identity='a'*64
        receipt={'source_identity':identity,'status':'pass','inputs':{'lib/one.dart':{'bytes':len(source),'sha256':M.digest(source)}},'count':1}
        raw=json.dumps(receipt).encode();(root/'receipt.json').write_bytes(raw)
        return {'format':M.FORMAT,'candidate':{'id':'synthetic','source_manifest_sha256':identity,'identity_bindings':[{'document':'receipt','pointer':'/source_identity'}]},
            'resources':{'workspace':'.'},'documents':{'receipt':{'path':'receipt.json','sha256':M.digest(raw),'bytes':len(raw)}},
            'file_sets':{'source':{'document':'receipt','pointer':'/inputs','shape':'map-metadata','expected_count':1,'resource':'workspace','prefix':'','role':'source','scope':'one synthetic file','closed_inventory':None}},
            'facts':[{'id':'count','kind':'json-pointer','document':'receipt','pointer':'/count','expected':1}],
            'evidence':[{'id':'proof','observed_result':'pass','result_binding':{'document':'receipt','pointer':'/status'},'context':'captured-candidate','validation_status':'retained-independent-scoped-readback','independent_receipt':'receipt','file_sets':['source'],'supersedes':[],'scope':'synthetic byte binding','limitations':['No visual or external acceptance']}],
            'acceptance_boundaries':{'full_visual_acceptance':'unverified','font_distribution_rights':'unverified','hosted_candidate_parity':'unverified','complete_packaged_SBOM':'unverified','production_release_approval':False}}

    def test_matched_list_does_not_become_complete_graph_or_acceptance(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);result=M.verify(self.fixture(root),root)
            self.assertEqual(result['errors'],[])
            self.assertEqual(result['evidence'][0]['listed_bindings'],'matched')
            self.assertEqual(result['evidence'][0]['input_set_completeness'],'unknown')
            self.assertFalse(result['PD12_closed']);self.assertFalse(result['acceptance_boundaries']['production_release_approval'])

    def test_changed_and_missing_bytes_retain_result_but_deny_current_binding(self):
        for mode in ['changed','missing']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);index=self.fixture(root)
                if mode=='changed':(root/'lib/one.dart').write_bytes(b'changed\n')
                else:(root/'lib/one.dart').unlink()
                result=M.verify(index,root)
                self.assertEqual(result['evidence'][0]['declared_result'],'pass')
                self.assertEqual(result['evidence'][0]['listed_bindings'],'drift')
                self.assertTrue(result['errors'])

    def test_closed_declared_set_detects_added_transitive_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root)
            index['file_sets']['source']['closed_inventory']={'basis_document':'receipt','directories':['lib'],'include_patterns':['lib/*.dart']}
            self.assertEqual(M.verify(index,root)['file_sets']['source']['inventory_status'],'closed-declared-set-matched')
            (root/'lib/new.dart').write_bytes(b'new input\n')
            self.assertTrue(M.verify(index,root)['errors'])

    def test_candidate_identity_and_receipt_result_cannot_be_forged(self):
        for mode in ['candidate','result','receipt']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);index=self.fixture(root)
                if mode=='candidate':
                    index['candidate']['source_manifest_sha256']='b'*64
                    with self.assertRaisesRegex(M.EvidenceIndexError,'candidate-source-identity-mismatch'):M.verify(index,root)
                elif mode=='receipt':
                    (root/'receipt.json').write_bytes(b'{}')
                    with self.assertRaisesRegex(M.EvidenceIndexError,'document-fence-mismatch'):M.verify(index,root)
                else:
                    index['evidence'][0]['observed_result']='complete-package-pass'
                    self.assertTrue(M.verify(index,root)['errors'])

    def test_wrong_fact_type_or_omitted_manifest_entry_is_not_a_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root);index['facts'][0]['expected']=True
            self.assertTrue(M.verify(index,root)['errors'])
            index['file_sets']['source']['expected_count']=2
            with self.assertRaisesRegex(M.EvidenceIndexError,'manifest-count-mismatch'):M.verify(index,root)

    def test_symlinks_and_traversal_cannot_supply_bound_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root)
            original=(root/'lib/one.dart').read_bytes();(root/'elsewhere').write_bytes(original)
            (root/'lib/one.dart').unlink();(root/'lib/one.dart').symlink_to(root/'elsewhere')
            self.assertTrue(M.verify(index,root)['errors'])
            index['file_sets']['source']['unproved_symlink_bindings']=True
            limited=M.verify(index,root);self.assertEqual(limited['evidence'][0]['listed_bindings'],'incomplete')
            self.assertEqual(limited['file_sets']['source']['matched'],0);self.assertFalse(limited['PD12_closed'])
            with self.assertRaisesRegex(M.EvidenceIndexError,'unsafe-path'):M.parts('../elsewhere')

    def test_nonregular_unknown_and_superseded_failures_are_retained(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root)
            historical={'status':'failed','inputs':{'old/directory':{'kind':'directory','mode':493}}}
            raw=json.dumps(historical).encode();(root/'old.json').write_bytes(raw)
            index['documents']['old']={'path':'old.json','sha256':M.digest(raw),'bytes':len(raw)}
            index['file_sets']['old-inputs']={**index['file_sets']['source'],'document':'old','scope':'unsupported historical physical entry'}
            old=copy.deepcopy(index['evidence'][0]);old.update({'id':'historical','context':'historical','observed_result':'failed','result_binding':{'document':'old','pointer':'/status'},'file_sets':['old-inputs'],'independent_receipt':None,'validation_status':'source-receipt-only'})
            index['evidence'][0]['supersedes']=['historical'];index['evidence'].append(old)
            result=M.verify(index,root)
            self.assertEqual(len(result['evidence']),2);self.assertEqual(result['evidence'][0]['supersedes'],['historical'])
            self.assertEqual(result['evidence'][1]['declared_result'],'failed');self.assertEqual(result['evidence'][1]['listed_bindings'],'incomplete')
            self.assertEqual(len(result['file_sets']['old-inputs']['unknown_entries']),1)
            index['evidence'][1]['supersedes']=['proof']
            with self.assertRaisesRegex(M.EvidenceIndexError,'supersession-cycle'):M.verify(index,root)

    def test_checksum_manifest_and_artifact_only_scope_preserve_unknown_input_coverage(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root);raw=(M.digest((root/'lib/one.dart').read_bytes())+'  lib/one.dart\n').encode()
            (root/'checksums').write_bytes(raw);index['documents']['checksums']={'path':'checksums','sha256':M.digest(raw),'bytes':len(raw),'content':'text'}
            index['file_sets']['source'].update({'document':'checksums','pointer':'','shape':'checksum-lines','role':'artifact'})
            result=M.verify(index,root);self.assertEqual(result['errors'],[])
            self.assertEqual(result['evidence'][0]['input_set_completeness'],'unknown')

    def test_composition_override_requires_pinned_receipt_and_updates_only_explicit_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root);new=b'new explicitly composed workflow\n';(root/'lib/one.dart').write_bytes(new)
            raw=json.dumps({'allowed_digest':M.digest(new)}).encode();(root/'composition.json').write_bytes(raw)
            index['documents']['composition']={'path':'composition.json','sha256':M.digest(raw),'bytes':len(raw)}
            index['file_sets']['source']['digest_overrides']={'lib/one.dart':{'document':'composition','pointer':'/allowed_digest'}}
            self.assertEqual(M.verify(index,root)['errors'],[])
            (root/'composition.json').write_bytes(b'{}')
            with self.assertRaisesRegex(M.EvidenceIndexError,'document-fence-mismatch'):M.verify(index,root)

    def test_current_tooling_drift_does_not_rewrite_archived_or_unchanged_app_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root);archived=root/'captured';(archived/'lib').mkdir(parents=True)
            (archived/'lib/one.dart').write_bytes((root/'lib/one.dart').read_bytes());index['resources']['archived']=str(archived)
            index['file_sets']['archived']={**index['file_sets']['source'],'resource':'archived','binding_domain':'archived-tested-candidate'}
            index['file_sets']['source']['binding_domain']='current-relevant-listed-inputs'
            (root/'scripts').mkdir();old=b'old audit source\n';(root/'scripts/audit.py').write_bytes(b'new audit source\n')
            raw=json.dumps({'inputs':{'scripts/audit.py':{'sha256':M.digest(old),'bytes':len(old)}}}).encode();(root/'tooling.json').write_bytes(raw)
            index['documents']['tooling']={'path':'tooling.json','sha256':M.digest(raw),'bytes':len(raw)}
            index['file_sets']['tooling']={**index['file_sets']['source'],'document':'tooling','role':'verification-tooling','binding_domain':'separate-maintained-tooling'}
            result=M.verify(index,root)
            self.assertEqual(result['file_sets']['archived']['matched'],1);self.assertEqual(result['file_sets']['source']['matched'],1)
            self.assertTrue(result['file_sets']['tooling']['failed']);self.assertEqual(result['evidence'][0]['declared_result'],'pass')
            self.assertFalse(result['PD12_closed'])

    def test_scope_projection_cannot_silently_omit_another_consumer_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);index=self.fixture(root);receipt=json.loads((root/'receipt.json').read_bytes())
            receipt['projected']=copy.deepcopy(receipt['inputs']);raw=json.dumps(receipt).encode();(root/'receipt.json').write_bytes(raw)
            index['documents']['receipt'].update({'sha256':M.digest(raw),'bytes':len(raw)})
            index['scope_relations']=[{'original_document':'receipt','original_pointer':'/inputs','projected_document':'receipt','projected_pointer':'/projected','excluded_exact_paths':[]}]
            self.assertEqual(M.verify(index,root)['errors'],[])
            receipt['projected']={};raw=json.dumps(receipt).encode();(root/'receipt.json').write_bytes(raw)
            index['documents']['receipt'].update({'sha256':M.digest(raw),'bytes':len(raw)})
            with self.assertRaisesRegex(M.EvidenceIndexError,'scope-projection-mismatch'):M.verify(index,root)

    def test_leaf_replacement_while_reading_cannot_supply_current_path_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root);path=root/'lib/one.dart';original=path.read_bytes();real_read=M.os.read;replaced=False
            def replace_after_first_block(fd,size):
                nonlocal replaced
                block=real_read(fd,size)
                if block==original and not replaced:
                    replaced=True;path.unlink();path.write_bytes(original)
                return block
            with mock.patch.object(M.os,'read',side_effect=replace_after_first_block):
                with self.assertRaisesRegex(M.EvidenceIndexError,'file-changed-during-read|file-path-changed-during-read'):
                    M.Reader().read(root,'lib/one.dart')
            self.assertTrue(replaced)

    def test_ancestor_replacement_while_reading_cannot_keep_old_directory_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root);original=(root/'lib/one.dart').read_bytes();real_read=M.os.read;replaced=False
            def replace_directory_after_first_block(fd,size):
                nonlocal replaced
                block=real_read(fd,size)
                if block==original and not replaced:
                    replaced=True;(root/'lib').rename(root/'old-lib');(root/'lib').mkdir();(root/'lib/one.dart').write_bytes(original)
                return block
            with mock.patch.object(M.os,'read',side_effect=replace_directory_after_first_block):
                with self.assertRaisesRegex(M.EvidenceIndexError,'directory-path-changed-during-read'):
                    M.Reader().read(root,'lib/one.dart')
            self.assertTrue(replaced)

    def test_artifact_or_execution_match_cannot_grant_visual_font_hosted_or_SBOM_acceptance(self):
        for key,value in [('full_visual_acceptance','verified'),('font_distribution_rights','licensed'),('hosted_candidate_parity','matched'),('complete_packaged_SBOM','complete'),('production_release_approval',True)]:
            with self.subTest(key=key),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);index=self.fixture(root);index['acceptance_boundaries'][key]=value
                with self.assertRaisesRegex(M.EvidenceIndexError,'unsupported-acceptance-claim'):M.verify(index,root)

if __name__=='__main__':unittest.main(verbosity=2)
