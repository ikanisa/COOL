#!/usr/bin/env python3
"""Verify Collect's explicit Android backup exclusions and their fail-closed edges.

This checks configured policy. Actual packaged-resource and OEM transfer behavior
require their own release evidence.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
DOMAINS = frozenset({
    "root", "file", "database", "sharedpref", "external",
    "device_root", "device_file", "device_database", "device_sharedpref",
})
SECTIONS = frozenset({"cloud-backup", "device-transfer"})


def parse_xml(raw):
    if len(raw) > 65536 or b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
        raise ValueError("Unsupported backup policy XML")
    try:
        return ET.fromstring(raw)
    except ET.ParseError as exc:
        raise ValueError("Unreadable backup policy XML") from exc


def verify_policy(manifest_bytes, rules_bytes):
    manifest = parse_xml(manifest_bytes)
    applications = manifest.findall("application")
    if manifest.tag != "manifest" or len(applications) != 1:
        raise ValueError("One application manifest is required")
    application = applications[0]
    required = {
        "allowBackup": "false",
        "fullBackupContent": "false",
        "dataExtractionRules": "@xml/data_extraction_rules",
    }
    if any(application.get(ANDROID + key) != value
           for key, value in required.items()):
        raise ValueError("Backup opt-out and extraction resource must stay bound")

    rules = parse_xml(rules_bytes)
    sections = list(rules)
    if (rules.tag != "data-extraction-rules" or rules.attrib
            or len(sections) != 2 or {e.tag for e in sections} != SECTIONS):
        raise ValueError("Only the two existing backup sections are allowed")
    for section in sections:
        expected_attrs = ({"disableIfNoEncryptionCapabilities": "true"}
                          if section.tag == "cloud-backup" else {})
        if section.attrib != expected_attrs:
            raise ValueError("Backup section attributes changed")
        exclusions = list(section)
        if len(exclusions) != len(DOMAINS):
            raise ValueError("Every Android data domain must be excluded once")
        seen = set()
        for exclusion in exclusions:
            domain = exclusion.get("domain")
            if (exclusion.tag != "exclude" or list(exclusion)
                    or set(exclusion.attrib) != {"domain", "path"}
                    or domain not in DOMAINS or domain in seen
                    or exclusion.get("path") != "."):
                raise ValueError("Exclusions must cover each whole domain")
            seen.add(domain)
        if seen != DOMAINS:
            raise ValueError("Incomplete recursive data exclusion")
    return {"sections": sorted(SECTIONS), "excluded_domains": sorted(DOMAINS)}


class AndroidBackupPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = ROOT / "android/app/src/main"
        cls.manifest = (base / "AndroidManifest.xml").read_bytes()
        cls.rules = (base / "res/xml/data_extraction_rules.xml").read_bytes()

    def assert_refused(self, *, manifest=None, rules=None):
        with self.assertRaises(ValueError):
            verify_policy(manifest if manifest is not None else self.manifest,
                          rules if rules is not None else self.rules)

    def test_current_application_and_resource_exclude_all_nine_domains(self):
        actual = verify_policy(self.manifest, self.rules)
        self.assertEqual(actual["excluded_domains"], sorted(DOMAINS))
        self.assertEqual(actual["sections"], sorted(SECTIONS))

    def test_missing_either_transfer_section_is_refused(self):
        for tag in SECTIONS:
            with self.subTest(section=tag):
                tree = parse_xml(self.rules)
                tree.remove(tree.find(tag))
                self.assert_refused(rules=ET.tostring(tree))

    def test_missing_any_domain_in_either_section_is_refused(self):
        for section in parse_xml(self.rules):
            for exclusion in section:
                with self.subTest(section=section.tag, domain=exclusion.get("domain")):
                    tree = parse_xml(self.rules)
                    target = tree.find(section.tag)
                    target.remove(next(e for e in target
                                       if e.get("domain") == exclusion.get("domain")))
                    self.assert_refused(rules=ET.tostring(tree))

    def test_narrower_exclusion_leaves_real_sibling_state_unprotected(self):
        for section in parse_xml(self.rules):
            for exclusion in section:
                with self.subTest(section=section.tag, domain=exclusion.get("domain")):
                    tree = parse_xml(self.rules)
                    target = next(e for e in tree.find(section.tag)
                                  if e.get("domain") == exclusion.get("domain"))
                    target.set("path", "collect_sms_access.xml")
                    self.assert_refused(rules=ET.tostring(tree))

    def test_old_sms_only_policy_is_refused(self):
        tree = parse_xml(self.rules)
        for section in tree:
            section[:] = [ET.Element("exclude", {
                "domain": "sharedpref", "path": "collect_sms_access.xml",
            })]
        self.assert_refused(rules=ET.tostring(tree))

    def test_include_or_duplicate_cannot_replace_a_missing_domain(self):
        for replacement in ("include", "duplicate"):
            with self.subTest(replacement=replacement):
                tree = parse_xml(self.rules)
                section = tree.find("device-transfer")
                if replacement == "include":
                    section[0].tag = "include"
                else:
                    section[0].set("domain", section[1].get("domain"))
                self.assert_refused(rules=ET.tostring(tree))

    def test_new_transfer_capability_or_unknown_section_is_refused(self):
        for tag in ("cross-platform-transfer", "other-transfer"):
            with self.subTest(section=tag):
                tree = parse_xml(self.rules)
                tree.append(ET.Element(tag))
                self.assert_refused(rules=ET.tostring(tree))

    def test_permissive_manifest_flags_or_detached_resource_are_refused(self):
        for key, value in (("allowBackup", "true"),
                           ("fullBackupContent", "@xml/permissive_backup"),
                           ("dataExtractionRules", "@xml/other_rules")):
            with self.subTest(attribute=key):
                tree = parse_xml(self.manifest)
                tree.find("application").set(ANDROID + key, value)
                self.assert_refused(manifest=ET.tostring(tree))

    def test_absent_manifest_flags_are_refused(self):
        for key in ("allowBackup", "fullBackupContent", "dataExtractionRules"):
            with self.subTest(attribute=key):
                tree = parse_xml(self.manifest)
                del tree.find("application").attrib[ANDROID + key]
                self.assert_refused(manifest=ET.tostring(tree))

    def test_cloud_encryption_guard_and_unknown_attributes_are_refused(self):
        tree = parse_xml(self.rules)
        tree.find("cloud-backup").set("disableIfNoEncryptionCapabilities", "false")
        self.assert_refused(rules=ET.tostring(tree))
        tree = parse_xml(self.rules)
        tree.find("device-transfer").set("enabled", "true")
        self.assert_refused(rules=ET.tostring(tree))

    def test_nested_rule_and_absolute_or_parent_path_are_refused(self):
        for path in ("/", "..", "./sensitive", ""):
            with self.subTest(path=path):
                tree = parse_xml(self.rules)
                tree.find("device-transfer")[0].set("path", path)
                self.assert_refused(rules=ET.tostring(tree))
        tree = parse_xml(self.rules)
        tree.find("device-transfer")[0].append(ET.Element("exclude"))
        self.assert_refused(rules=ET.tostring(tree))

    def test_malformed_or_entity_document_is_refused(self):
        for raw in (b"<data-extraction-rules>",
                    b'<!DOCTYPE x [<!ENTITY y "data">]><data-extraction-rules/>',
                    b" " * 65537):
            with self.subTest(size=len(raw)):
                self.assert_refused(rules=raw)


if __name__ == "__main__":
    unittest.main()
