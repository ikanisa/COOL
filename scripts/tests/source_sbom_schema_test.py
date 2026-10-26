#!/usr/bin/env python3
"""Retained schema identity, offline validation and mutation refusals."""
import importlib.util
import json
from pathlib import Path
import shutil
import socket
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('source_sbom_schema',ROOT/'scripts/supply_chain/validate_source_sbom.py')
validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)

class SourceSbomSchemaTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.schemas=self.root/'schema';shutil.copytree(validator.SCHEMAS,self.schemas)
        self.document=self.root/'bom.json'
        self.document.write_text(json.dumps({'bomFormat':'CycloneDX','specVersion':'1.6','version':1,'components':[{'type':'library','name':'synthetic-fixture','version':'1.0'}]}))
        self.original=validator.SCHEMAS;validator.SCHEMAS=self.schemas
        self.addCleanup(setattr,validator,'SCHEMAS',self.original)

    def test_retained_default_schema_validates_valid_document_without_network(self):
        with patch.object(socket,'socket',side_effect=AssertionError('Offline schema validation attempted network')):
            self.assertEqual(validator.validate(self.document),[])

    def test_invalid_document_returns_real_schema_errors(self):
        document=json.loads(self.document.read_text());document['bomFormat']='not-CycloneDX';self.document.write_text(json.dumps(document))
        self.assertTrue(validator.validate(self.document))

    def test_modified_schema_is_refused(self):
        p=self.schemas/'bom-1.6.schema.json';p.write_bytes(p.read_bytes()+b' ')
        with self.assertRaisesRegex(ValueError,'Retained schema drift'):
            validator.validate(self.document)

    def test_rewriting_provenance_cannot_bless_modified_schema(self):
        import hashlib
        p=self.schemas/'bom-1.6.schema.json';p.write_bytes(p.read_bytes()+b' ')
        q=self.schemas/'provenance.json';d=json.loads(q.read_text());d['schema_files'][p.name]=hashlib.sha256(p.read_bytes()).hexdigest();q.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'schema provenance drift'):
            validator.validate(self.document)

    def test_missing_schema_is_a_refusal(self):
        (self.schemas/'spdx.schema.json').unlink()
        with self.assertRaises(FileNotFoundError):validator.validate(self.document)

    def test_changed_provenance_origin_is_refused(self):
        p=self.schemas/'provenance.json';d=json.loads(p.read_text());d['source_repository']='https://foreign.invalid/schema';p.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'schema provenance drift'):validator.validate(self.document)

if __name__=='__main__':unittest.main(verbosity=2)
