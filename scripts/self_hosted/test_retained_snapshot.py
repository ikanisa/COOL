import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from scripts.self_hosted.retained_snapshot import physical_directory, validate_tar, verify_snapshot, restore_roles_sql, restore_database_properties


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


if __name__ == '__main__':
    unittest.main()
