import pathlib, hashlib, json, subprocess, shutil, datetime
ROOT = pathlib.Path(__file__).resolve().parents[3]
STAGE = pathlib.Path(__file__).resolve().parent
PACKET = ROOT / '.cache/receipt-full-candidate-rehearsal-20261002'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(PACKET / 'MANIFEST.json') == 'cb7490907207b539d841a4974959914cf46c837825aac192b15cf236ec495a23'
assert sha(PACKET / 'VERIFICATION.json') == 'c59340e8450e6856c81881ad92b0d3898db1f384df4fc3a7bbb604368c240039'
members = json.loads((PACKET / 'MANIFEST.json').read_text())['members']
assert len(members) == 1543
for name, digest in members.items():
    p = PACKET / name
    assert p.is_file() and not p.is_symlink() and sha(p) == digest, name
verification = json.loads((PACKET / 'VERIFICATION.json').read_text())
result = json.loads((PACKET / 'full208-attempt3/result.json').read_text())
assert result['status'] == 'pass' and len(result['cases']) == 50
assert all(c['status'] == 'pass' for c in result['cases'])
assert all(len(p['migrations']) == 208 and p['status'] == 'pass' for p in result['phases'].values())
assert len(verification['final_source_readback']) == 208
assert all(sha(ROOT / n) == h for n, h in verification['final_source_readback'].items())
names = [p['container_name'] for attempt in ['full208-attempt1', 'full208-attempt2', 'full208-attempt3']
         for p in json.loads((PACKET / attempt / 'result.json').read_text())['phases'].values()]
assert len(names) == len(set(names)) == 5
absent = []
for i, name in enumerate(names):
    c = subprocess.run(['/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker', 'inspect', name],
                       capture_output=True, timeout=15)
    (STAGE / f'inspect-{i}.stdout').write_bytes(c.stdout)
    (STAGE / f'inspect-{i}.stderr').write_bytes(c.stderr)
    assert c.returncode != 0 and b'no such object:' in c.stderr.lower(), (name, c.returncode)
    absent.append({'name': name, 'exit_code': c.returncode, 'stderr_sha256': hashlib.sha256(c.stderr).hexdigest(), 'absent': True})
out = ROOT / 'docs/release/collect-codex-goal-2026-09-30/full208-migration-installation-20261002'
out.mkdir(exist_ok=False)
for name in list(members) + ['MANIFEST.json', 'SEAL.json']:
    target = out / 'packet' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PACKET / name, target)
    assert sha(target) == sha(PACKET / name)
review = {'status': 'root_verified_and_copied', 'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'packet_member_count': 1543, 'source_migrations': 208, 'applications': 416, 'checks': 50,
    'projection_scope': '18 declared column projections across84 post124 migrations;7configuration vectors',
    'v4_result': verification['v4_actual_result'], 'root_direct_target_absence': absent, 'source_graph_current': True,
    'manifest_sha256': sha(PACKET / 'MANIFEST.json'), 'verification_sha256': sha(PACKET / 'VERIFICATION.json'),
    'limits': 'Privileged platform bootstrap; NOSUPERUSER installer retains CREATEDB/CREATEROLE/BYPASSRLS/inherited trusted roles; synthetic Auth/Storage; no hosted/runtime/full recovery/device/release GO'}
(out / 'ROOT_REVIEW.json').write_text(json.dumps(review, indent=2) + '\n')
(out / 'README.md').write_text('''# Full208 migration installation — local candidate evidence

All208 frozen canonical migrations passed on each clean and populated database:416 applications and50 checks, including all36 original ordinary-installer checks. Root verified the complete1543-member packet and current208 migration hashes, then independently confirmed all five owned targets from the retained attempts were absent.

The populated fixture preserves18 declared financial/receipt/Auth/approval column projections before and after all84 later migrations. Seven configuration vectors record the intentional Rwanda-scope and two Admin-navigation changes. This proves the declared synthetic projections, not all hosted data. The finite read seam records empty/unavailable/inactive states and the actual42501 email-owner denial from its unchanged phone-only fixture; it creates no owner, approval, run or send.

The application installer is actually postgresNOSUPERUSER after privileged platform bootstrap; CREATEDB,CREATEROLE,BYPASSRLS and trusted inherited roles remain local fixture limitations. Auth/Storage is a retained schema prelude. Hosted owner/extension/ACL/Auth parity, complete runtime regression, full current recovery, physical device, visual/comparator, distribution and release acceptance remain separate.

`packet/` is an exact finite copy of the sealed source, result, command, failure and cleanup receipts. Original failures remain failed; their416 applications/43 checks are not added to the successful final run. `ROOT_REVIEW.json` binds root readback and direct target absence. The installation freeze is distinct from a final product/artifact release freeze. These copied drivers are evidence of their original executed paths, not an instruction to execute them from this documentation directory.
''')
shutil.copy2(__file__, out / 'root-verify-copy.py')
shutil.copy2(STAGE / 'failure1.json', out / 'root-reviewer-failure1.json')
for p in STAGE.glob('inspect-*.*'):
    shutil.copy2(p, out / 'root-target-inspection' / p.name) if (out / 'root-target-inspection').exists() else None
(out / 'root-target-inspection').mkdir(exist_ok=True)
for p in STAGE.glob('inspect-*.*'):
    shutil.copy2(p, out / 'root-target-inspection' / p.name)
rows = [(sha(p), str(p.relative_to(out))) for p in out.rglob('*') if p.is_file()]
(out / 'FILES_SHA256').write_text(''.join(h + '  ' + n + '\n' for h, n in sorted(rows, key=lambda x: x[1])))
print(json.dumps({'status': 'root_verified_and_copied', 'capsule': str(out), 'members': len(rows),
                  'files_sha256': sha(out / 'FILES_SHA256'), 'direct_absent_targets': len(absent)}))
