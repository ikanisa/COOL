from pathlib import Path
import difflib,hashlib,json
ROOT=Path.cwd();STAGE=ROOT/'.cache/receipt-full-candidate-rehearsal-20261002';old=(ROOT/'scripts/tests/current_ordinary_installer_rehearsal.py').read_text();assert hashlib.sha256(old.encode()).hexdigest()=='c00f627704762d92632b9de9bb8f9fc0a8e233efbb6204310598c1bfeac5e3a6'
body=old
body=body.replace('import collect_current_release_upgrade_uat as replay', '''import hashlib
import importlib.util

# Exact existing helper, verified before first import; no target at import time.
REPOSITORY = Path(__file__).resolve().parents[2]
OWNED = REPOSITORY / '.cache/receipt-full-candidate-rehearsal-20261002'
HELPER = REPOSITORY / 'scripts/tests/collect_current_release_upgrade_uat.py'
HELPER_SHA256 = '343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b'
if hashlib.sha256(HELPER.read_bytes()).hexdigest() != HELPER_SHA256:
    raise RuntimeError('Reviewed ordinary helper predecessor drift')
spec = importlib.util.spec_from_file_location('collect_current_release_upgrade_uat', HELPER)
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
''')
body=body.replace('    parser.add_argument("--output", type=Path, required=True)', '''    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--inventory-sha256", required=True)''')
body=body.replace('if report.exists() or not report.is_relative_to(ROOT / "docs/release"):', 'if report.exists() or not report.is_relative_to(OWNED):')
body=body.replace('parser.error("Fresh local release evidence directory required")','parser.error("Fresh private owned evidence directory required")')
body=body.replace('    report.mkdir(mode=0o700, parents=True)', '''    freeze_bytes = args.inventory.resolve().read_bytes()
    if replay.sha(freeze_bytes) != args.inventory_sha256:
        raise RuntimeError('Root freeze inventory hash mismatch')
    freeze = json.loads(freeze_bytes)
    inventory = freeze.get('source_inventory')
    if inventory is None:
        vector = freeze.get('source_bindings', freeze.get('sha256'))
        if not isinstance(vector, dict):
            raise RuntimeError('Frozen source_inventory or source hash vector required')
        inventory = [{'path': path, 'sha256': digest} for path, digest in vector.items()
                     if path.startswith('supabase/migrations/') and path.endswith('.sql')]
    expected = {}
    for item in inventory:
        path = Path(item['path'])
        if path.parent != Path('supabase/migrations') or path.suffix != '.sql' or str(path) in expected:
            raise RuntimeError('Frozen migration path or duplicate invalid')
        expected[str(path)] = item['sha256']
    current = {str(p.relative_to(ROOT)): replay.sha(p.read_bytes())
               for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
    if not expected or expected != current:
        raise RuntimeError('Full current canonical graph differs from root freeze')
    report.mkdir(mode=0o700, parents=True)
    (report / 'root-frozen-inventory.json').write_bytes(freeze_bytes)''')
body=body.replace('    if len({i["version"] for i in items}) != len(items):','''    if {i['path']: i['sha256'] for i in items} != expected:
        raise RuntimeError('Frozen sources changed during capture')
    if len({i["version"] for i in items}) != len(items):''')
body=body.replace('helper_paths = [Path(__file__), Path(replay.__file__), TRANSPORT_PLATFORM]', "helper_paths = [Path(__file__), Path(replay.__file__), TRANSPORT_PLATFORM, OWNED / 'combined_reader_seam.py']")
body=body.replace('        source_inventory=[{k:v for k,v in i.items() if k != "body"} for i in items],','''        source_inventory=[{k:v for k,v in i.items() if k != "body"} for i in items],
        root_frozen_inventory_sha256=args.inventory_sha256,
        exact_full_current_graph=True,
        helper_sha256={str(p.relative_to(ROOT)):replay.sha(body)for p,body in helpers.items()},''')
body=body.replace('            replay.apply(target, [item], outcome)', '''            config_before = replay.fingerprints(target, evidence['config_columns']) if before is not None else None
            replay.apply(target, [item], outcome)''')
body=body.replace('                outcome["migrations"][-1]["canonical_predecessor_preserved"] = True', '''                outcome["migrations"][-1]["canonical_predecessor_preserved"] = True
                config_after = replay.fingerprints(target, evidence['config_columns'])
                outcome['migrations'][-1]['configuration_changed_tables'] = [key for key in config_before if config_before[key] != config_after[key]]
                outcome['migrations'][-1]['configuration_before'] = config_before
                outcome['migrations'][-1]['configuration_after'] = config_after''')
# Require the actual existing mount and task label; no arbitrary target attachment/cleanup.
body=body.replace('\ndef main():', '''\nclass OwnedTarget(replay.Target):
    def close(self):
        if self.made:
            labels = json.loads(replay.command([replay.DOCKER, 'inspect', self.name, '--format', '{{json .Config.Labels}}']).stdout)
            if labels.get('collect.rehearsal.owner') != self.name:
                raise RuntimeError('Owned target label changed; refusing non-owned cleanup')
        super().close()
        if self.evidence.get('task_container_removed'):
            observed = replay.command([replay.DOCKER, 'ps', '--all', '--quiet', '--filter', 'name=^/' + self.name + '$'])
            self.evidence['target_absence_verified'] = observed.stdout.strip() == ''
            if not self.evidence['target_absence_verified']:
                raise RuntimeError('Owned target remains after removal')


def main():''')
body=body.replace('target = replay.Target(report,', 'target = OwnedTarget(report,')
body=body.replace('            with target:\n', '''            with target:
                mounts = json.loads(replay.command([replay.DOCKER, 'inspect', target.name, '--format', '{{json .Mounts}}']).stdout)
                pgdata_mount = [m for m in mounts if m.get('Destination') == '/var/lib/postgresql/collect-rehearsal']
                case(phase + ' actual PostgreSQL data directory remains on owned tmpfs',
                     len(pgdata_mount) == 1 and pgdata_mount[0]['Type'] == 'tmpfs')
                outcome['actual_pgdata_mount'] = pgdata_mount[0]
''')
# Preserve original populated UAT and add only the approved read seam after all migrations.
body=body.replace('                    replay.verify_populated(target, evidence, case, len(items))', '''                    replay.verify_populated(target, evidence, case, len(items))
                    reader_path = report / 'combined_reader_seam.py'
                    reader_spec = importlib.util.spec_from_file_location('full_candidate_combined_reader_seam', reader_path)
                    reader = importlib.util.module_from_spec(reader_spec)
                    reader_spec.loader.exec_module(reader)
                    reader.run(replay, target, evidence, case)''')

body=body.replace('                outcome["ordinary_installer"] = ordinary(target)', '''                outcome["ordinary_installer"] = ordinary(target)
                outcome['installer_inherited_roles'] = target.json("select coalesce(jsonb_agg(jsonb_build_object('role',r.rolname,'usage',pg_has_role(current_user,r.oid,'USAGE'))order by r.rolname),'[]'::jsonb)from pg_roles r where r.rolname<>current_user and pg_has_role(current_user,r.oid,'MEMBER');")''')
body=body.replace('                ordinary(target)\n                outcome["scheduler_readback"]', '''                ordinary(target)
                outcome["scheduler_readback"]''')
# The context manager already cleans successful targets; close guard remains an independent final target absence check.
(STAGE/'full_candidate_ordinary_rehearsal.py').write_text(body)
(STAGE/'driver-base-aware.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),body.splitlines(True),fromfile='a/scripts/tests/current_ordinary_installer_rehearsal.py',tofile='b/.cache/receipt-full-candidate-rehearsal-20261002/full_candidate_ordinary_rehearsal.py')))
compile(body,str(STAGE/'full_candidate_ordinary_rehearsal.py'),'exec')
print(json.dumps({'status':'private_driver_prepared_syntax_only','base_sha256':hashlib.sha256(old.encode()).hexdigest(),'prepared_sha256':hashlib.sha256(body.encode()).hexdigest(),'target_created':False,'combined_reader_delta_pending_final440_freeze':True}))
