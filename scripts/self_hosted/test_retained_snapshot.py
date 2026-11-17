import io
import copy
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from scripts.self_hosted.retained_snapshot import physical_directory, validate_tar, verify_snapshot, restore_roles_sql, restore_database_properties, require_owned_fresh_clone, require_fresh_restore_target, forward_restore_arguments, LABEL
from scripts.self_hosted.retained_snapshot import database_locale_arguments, require_database_locale, snapshot_database_locale


class RetainedSnapshotBoundary(unittest.TestCase):
    def test_regular_pg_file_is_accepted(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / 'snapshot.tar'
            with tarfile.open(path, 'w') as archive:
                entry = tarfile.TarInfo('PG_VERSION'); entry.size = 3
                archive.addfile(entry, io.BytesIO(b'17\n'))
            self.assertEqual(validate_tar(path), 1)

    def test_traversal_links_devices_and_duplicate_members_are_refused(self):
        with tempfile.TemporaryDirectory() as name:
            for index, (entry_name, kind) in enumerate([
                    ('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                    ('linked', tarfile.SYMTYPE), ('hard', tarfile.LNKTYPE),
                    ('device', tarfile.CHRTYPE), ('pipe', tarfile.FIFOTYPE)]):
                with self.subTest(entry_name=entry_name):
                    path = Path(name) / f'{index}.tar'
                    with tarfile.open(path, 'w') as archive:
                        entry = tarfile.TarInfo(entry_name); entry.type = kind
                        entry.linkname = '/outside'; archive.addfile(entry)
                    with self.assertRaises(ValueError): validate_tar(path)
            path = Path(name) / 'duplicate.tar'
            with tarfile.open(path, 'w') as archive:
                archive.addfile(tarfile.TarInfo('PG_VERSION'))
                archive.addfile(tarfile.TarInfo('./PG_VERSION'))
            with self.assertRaisesRegex(ValueError, 'Duplicate'): validate_tar(path)

    def test_directory_must_be_private_and_cannot_traverse_a_link(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name).resolve()
            self.assertEqual(physical_directory(root), root)
            root.chmod(0o750)
            with self.assertRaisesRegex(ValueError, 'Owner-only'): physical_directory(root)
            root.chmod(0o700)
            link = root / 'link'; link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Physical'): physical_directory(link)

    def test_snapshot_receipt_cannot_name_arbitrary_files(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name).resolve()
            (root / 'snapshot.json').write_text(json.dumps({
                'format': 'collect.retained.pg17.snapshot.v3',
                'operation_id': '4b95e9ae-5ad5-4d43-8b8d-2bbf9fa79de3',
                'bootstrap_role': 'supabase_admin',
                'image_id': 'sha256:' + 'a' * 64,
                'files': {'../outside': {'sha256': 'b' * 64, 'bytes': 1}}}))
            with self.assertRaisesRegex(ValueError, 'Exact private'): verify_snapshot(root)

    def test_bootstrap_identity_preserves_all_role_attributes_and_grants(self):
        sql='CREATE ROLE anon;\nCREATE ROLE supabase_admin;\nALTER ROLE supabase_admin SUPERUSER;\nGRANT anon TO postgres WITH ADMIN OPTION GRANTED BY supabase_admin;\n'
        rendered=restore_roles_sql(sql,'supabase_admin')
        self.assertEqual(rendered,sql.replace('CREATE ROLE supabase_admin;\n',''))
        with self.assertRaises(ValueError):restore_roles_sql(sql,'another_superuser')
        with self.assertRaises(ValueError):restore_roles_sql(sql+sql,'supabase_admin')

    def test_database_owner_grantor_and_private_settings_are_preserved(self):
        value={'owner':'postgres','acl':[{'grantor':'postgres','grantee':'PUBLIC','privilege':'CONNECT','grantable':False}],
               'settings':["app.settings.key=private'value"]}
        sql=restore_database_properties(value)
        self.assertIn('OWNER TO "postgres"',sql)
        self.assertIn('SET LOCAL ROLE "postgres"',sql)
        self.assertIn("TO 'private''value'",sql)
        value['acl'][0]['privilege']='SUPERUSER'
        with self.assertRaises(ValueError):restore_database_properties(value)


class FreshForwardRestoreBoundary(unittest.TestCase):
    def setUp(self):
        self.identity = 'a' * 64
        self.receipt = {'operation_id': '4b95e9ae-5ad5-4d43-8b8d-2bbf9fa79de3',
                        'source_container_id': 'b' * 64, 'image_id': 'sha256:' + 'c' * 64}
        self.volume = 'collect-buri-rehearsal-4b95e9ae-data'
        self.container = {'Id': self.identity, 'Image': self.receipt['image_id'],
            'Name': '/collect-buri-rehearsal-4b95e9ae', 'State': {'Running': True},
            'Config': {'Labels': {LABEL: self.receipt['operation_id']}},
            'HostConfig': {'NetworkMode': 'none', 'PortBindings': {}},
            'NetworkSettings': {'Ports': {'5432/tcp': None}},
            'Mounts': [{'Type': 'volume', 'Name': self.volume, 'Destination': '/var/lib/postgresql', 'RW': True}]}
        self.fresh = {'major': 17, 'database': 'postgres', 'current_user': 'supabase_admin',
            'session_user': 'supabase_admin', 'bootstrap_role': 'supabase_admin',
            'custom_schemas': [], 'user_relations': 0, 'user_functions': 0,
            'extensions': ['plpgsql'], 'foreign_servers': 0, 'event_triggers': 0, 'publications': 0}

    def test_measured_fresh_owned_native_clone_uses_strict_forward_restore(self):
        require_owned_fresh_clone(self.container, self.receipt, self.identity, self.volume)
        self.assertEqual(require_fresh_restore_target(self.fresh, 'supabase_admin')['restore_method'], 'forward_only')
        args = forward_restore_arguments(self.identity, 'supabase_admin')
        self.assertIn('--single-transaction', args)
        self.assertIn('--exit-on-error', args)
        self.assertNotIn('--clean', args)
        self.assertNotIn('--if-exists', args)
        self.assertNotIn('--no-owner', args)
        self.assertNotIn('--no-acl', args)

    def test_source_identity_labels_image_network_mount_or_ports_cannot_be_substituted(self):
        changes = [({'Id': 'b' * 64}), ({'Image': 'sha256:' + 'd' * 64}),
            ({'Name': '/supabase_db_local-app'}), ({'State': {'Running': False}}),
            ({'Config': {'Labels': {LABEL: 'different'}}}),
            ({'HostConfig': {'NetworkMode': 'bridge'}}),
            ({'NetworkSettings': {'Ports': {'5432/tcp': [{'HostPort': '55102'}]}}}),
            ({'Mounts': [{'Type': 'bind', 'Name': self.volume, 'Destination': '/var/lib/postgresql', 'RW': True}]}),
            ({'Mounts': [{'Type': 'volume', 'Name': 'source-native-volume', 'Destination': '/var/lib/postgresql', 'RW': True}]})]
        for change in changes:
            with self.subTest(change=change):
                actual = copy.deepcopy(self.container); actual.update(change)
                with self.assertRaises(ValueError): require_owned_fresh_clone(actual, self.receipt, self.identity, self.volume)
        with self.assertRaises(ValueError):
            require_owned_fresh_clone(self.container, {**self.receipt, 'source_container_id': self.identity}, self.identity, self.volume)

    def test_any_unproven_or_existing_native_schema_state_refuses_forward_restore(self):
        changes = {'major': 16, 'database': 'another', 'current_user': 'postgres',
            'session_user': 'postgres', 'bootstrap_role': 'postgres',
            'custom_schemas': ['auth'], 'user_relations': 1, 'user_functions': 1,
            'extensions': ['plpgsql', 'pgcrypto'], 'foreign_servers': 1, 'event_triggers': 1, 'publications': 1}
        for key, value in changes.items():
            with self.subTest(field=key):
                with self.assertRaises(ValueError): require_fresh_restore_target({**self.fresh, key: value}, 'supabase_admin')
        with self.assertRaises(ValueError): require_fresh_restore_target({k:v for k,v in self.fresh.items() if k!='user_functions'}, 'supabase_admin')
        with self.assertRaises(ValueError): require_fresh_restore_target(self.fresh, 'another_superuser')


class DatabaseLocaleRecoveryBoundary(unittest.TestCase):
    def setUp(self):
        # Actual retained PG17 observation: the prior hardcoded C.UTF-8 clone
        # changed both its source locale and ICU provider.
        self.locale = {'encoding': 'UTF8', 'provider': 'i', 'collate': 'en_US.UTF-8',
                       'ctype': 'en_US.UTF-8', 'locale': 'en-US', 'icu_rules': None, 'version': '153.121'}

    def test_actual_native_icu_provider_locale_and_character_categories_are_preserved(self):
        args = database_locale_arguments(self.locale)
        self.assertIn('--locale-provider=icu', args)
        self.assertIn('--icu-locale=en-US', args)
        self.assertIn('--lc-collate=en_US.UTF-8', args)
        self.assertIn('--lc-ctype=en_US.UTF-8', args)
        self.assertNotIn('--locale=C.UTF-8', args)
        require_database_locale(copy.deepcopy(self.locale), self.locale)

    def test_libc_and_distinct_character_categories_do_not_acquire_icu_defaults(self):
        value = {**self.locale, 'provider': 'c', 'locale': None, 'icu_rules': None,
                 'collate': 'C', 'ctype': 'C.UTF-8', 'version': None}
        args = database_locale_arguments(value)
        self.assertIn('--locale-provider=libc', args)
        self.assertIn('--lc-collate=C', args)
        self.assertIn('--lc-ctype=C.UTF-8', args)
        self.assertFalse(any(item.startswith('--icu-') for item in args))

    def test_icu_rules_remain_one_argument_without_shell_interpretation(self):
        rules = '&V < w <<< W'
        args = database_locale_arguments({**self.locale, 'icu_rules': rules})
        self.assertIn('--icu-rules=' + rules, args)

    def test_missing_unsupported_or_malformed_source_locale_is_refused(self):
        invalid = [{k:v for k,v in self.locale.items() if k != 'provider'},
                   {**self.locale, 'encoding': 'SQL_ASCII'}, {**self.locale, 'provider': 'b'},
                   {**self.locale, 'locale': None}, {**self.locale, 'version': None},
                   {**self.locale, 'collate': 'C\n--no-sync'}, {**self.locale, 'ctype': ''},
                   {**self.locale, 'locale': 'en-US\0x'}, {**self.locale, 'icu_rules': 'x\0'},
                   {**self.locale, 'provider': 'c'}]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                database_locale_arguments(value)

    def test_source_provider_locale_rules_and_version_must_match_before_data_restore(self):
        for key, value in {'encoding':'LATIN1', 'provider':'c', 'collate':'C.UTF-8',
                           'ctype':'C.UTF-8', 'locale':'fr-FR', 'icu_rules':'&V < w',
                           'version':'154.0'}.items():
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'differs'):
                require_database_locale({**self.locale, key:value}, self.locale)

    def test_legacy_snapshot_custody_does_not_invent_a_restore_locale(self):
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaisesRegex(ValueError, 'observed native database locale'):
                snapshot_database_locale(Path(name), {'format':'collect.retained.pg17.snapshot.v3'})


if __name__ == '__main__':
    unittest.main()
