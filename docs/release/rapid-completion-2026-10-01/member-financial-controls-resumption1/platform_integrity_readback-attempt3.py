#!/usr/bin/env python3
"""Read-only, task-label-bound catalog observer for the current Admin run."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'scripts/tests'))
import collect_current_release_upgrade_uat as R

PACKET = Path(__file__).resolve().parent
RUN = ROOT / 'docs/release/generated-query-benchmark-2026-10-01/admin-current-candidate-volumes3'
DUMP = ROOT / 'docs/release/runtime-controls-2026-10-01/current21-full26-races-attempt1/schema-only.sql'
raw = DUMP.read_text()
definitions = dict(re.findall(
    r'CREATE FUNCTION extensions\.(grant_pg_(?:cron|net)_access)\(\) RETURNS event_trigger.*?\bAS (\$[^$]*\$)(.*?)\2;', raw, re.S)) if False else {
        name: body for name, _, body in re.findall(
            r'CREATE FUNCTION extensions\.(grant_pg_(?:cron|net)_access)\(\) RETURNS event_trigger.*?\bAS (\$[^$]*\$)(.*?)\2;', raw, re.S)}
assert set(definitions) == {'grant_pg_cron_access', 'grant_pg_net_access'}
SQL = """begin read only;
select jsonb_build_object(
 'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),
 'hooks',(select jsonb_agg(jsonb_build_object('name',e.evtname,'enabled',e.evtenabled,'event',e.evtevent,'tags',e.evttags,'function',p.proname,'body',p.prosrc,'definition',pg_get_functiondef(p.oid))order by e.evtname)from pg_event_trigger e join pg_proc p on p.oid=e.evtfoid where e.evtname in('issue_pg_cron_access','issue_pg_net_access')),
 'triggers',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))order by n.nspname,c.relname,t.tgname)from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid join pg_namespace f on f.oid=p.pronamespace where not t.tgisinternal and(n.nspname='public'or n.nspname like 'collect_%'or f.nspname='public'or f.nspname like 'collect_%')),
 'constraints',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',k.conname,'validated',k.convalidated,'definition',pg_get_constraintdef(k.oid))order by n.nspname,c.relname,k.conname)from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'or n.nspname like 'collect_%'));
rollback;"""

def cmd(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()

result = dict(kind='read_only_task_owned_admin_volume_platform_integrity',
    observer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    dump_sha256=hashlib.sha256(DUMP.read_bytes()).hexdigest(),
    expected_hook_bodies=definitions, sql=SQL, observations=[], status='running',
    sql_mutations=False, shared_target_called=False)
deadline = time.monotonic() + 900
seen = set()
while time.monotonic() < deadline and len(seen) < 2:
    for volume in (1000, 10000):
        oracle = RUN / f'volume-{volume}/source-read-oracle.json'
        if volume in seen or not oracle.exists():
            continue
        names = cmd([R.DOCKER, 'ps', '--filter', 'name=collect_current_rehearsal_schema154_private_', '--format', '{{.Names}}']).splitlines()
        assert len(names) == 1, names
        name = names[0]
        config = json.loads(cmd([R.DOCKER, 'inspect', name]))[0]
        assert config['Config']['Labels']['collect.rehearsal.owner'] == name
        assert config['HostConfig']['NetworkMode'] == 'none' and not config['HostConfig']['PortBindings']
        value = subprocess.run([R.DOCKER, 'exec', '-i', name, 'psql', '-XqAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=SQL, capture_output=True, text=True)
        assert value.returncode == 0, value.stderr
        catalog = json.loads(value.stdout.strip())
        assert catalog['cron'] == 'off' and catalog['net'] == '0'
        assert len(catalog['hooks']) == 2
        for hook in catalog['hooks']:
            assert hook['enabled'] == 'O' and hook['event'] == 'ddl_command_end' and hook['tags'] == ['CREATE EXTENSION']
            assert hook['body'] == definitions[hook['function']]
        assert catalog['triggers'] and all(t['enabled'] != 'D' for t in catalog['triggers'])
        assert catalog['constraints']
        result['observations'].append(dict(volume=volume, container_name=name,
            task_label_verified=True, network='none', published_ports=False,
            synthetic_fixture_sha256=hashlib.sha256((oracle.parent/'synthetic-read-fixtures.sql').read_bytes()).hexdigest(),
            actual_catalog=catalog, hook_definitions_exact_dump_match=True,
            application_triggers_disabled=0, application_constraint_count=len(catalog['constraints'])))
        seen.add(volume)
        (PACKET/'platform-integrity-readback.json').write_text(json.dumps(result,indent=2)+'\n')
        print(f'PASS read-only catalog volume {volume}: {len(catalog["triggers"])} active triggers, {len(catalog["constraints"])} constraints', flush=True)
    if len(seen) < 2:
        terminal = RUN/'result.json'
        if terminal.exists() and json.loads(terminal.read_text()).get('status') in ('failed','pass_scoped'):
            break
        time.sleep(.2)
result['status'] = 'pass_scoped' if len(seen) == 2 else 'incomplete'
result['limits'] = 'Catalog read at each seeded query phase. Original hook source is exact accepted dump; constraints are observed metadata, not a substitute for migration/fixture acceptance.'
(PACKET/'platform-integrity-readback.json').write_text(json.dumps(result,indent=2)+'\n')
raise SystemExit(result['status'] != 'pass_scoped')
