from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
ORIGINAL = ROOT / 'supabase/functions/prepare-roster-import/handler_test.ts'
TEXT = ORIGINAL.read_text()
FIRST = TEXT.index('Deno.test("source hash')
POLICY = TEXT.index('// AI dispatch policy cases')
HELPERS = TEXT[TEXT.index('const ACTOR ='):FIRST]
CORE = TEXT[FIRST:POLICY]
POLICY_CASES = TEXT[POLICY:]


def named_import(path, names):
    return 'import {\n' + ''.join('  ' + name + ',\n' for name in names) + '} from "' + path + '";\n'


COMMON = 'import { assertEquals } from "../_shared/test_assert.ts";\n'
FIXTURE = (
    COMMON
    + 'import { SYNTHETIC_ROSTER_AI_CONFIGURATION } from "../_shared/roster_ai_dispatch_test_fixture.ts";\n'
    + 'import { normalizeRosterCandidates } from "../_shared/roster_import.ts";\n'
    + 'import { PublicError } from "../_shared/production_contract.ts";\n'
    + 'import { rosterSha256 } from "../_shared/roster_provenance.ts";\n'
    + named_import('./handler.ts', ['createRosterImportHandler', 'type RosterHandlerDependencies'])
    + '\n' + HELPERS
    + 'export {\n'
    + ''.join('  ' + name + ',\n' for name in [
        'ACTOR', 'ai', 'assert', 'base64', 'type Call', 'encoder', 'errorResponse',
        'EXPIRY', 'fixture', 'IMPORT', 'pasted', 'PNG', 'provider', 'rejects',
        'request', 'REQUEST', 'REVISION', 'SESSION', 'TEXT', 'token'])
    + '};\n'
)
CORE_IMPORTS = (
    COMMON
    + 'import { canonicalRwandaMomoNumber } from "../_shared/roster_import.ts";\n'
    + named_import('../_shared/roster_provenance.ts', [
        'readRosterSource', 'rosterCandidateJsonbBytes', 'rosterSession', 'rosterSha256'])
    + named_import('./handler_test_fixture.ts', [
        'ACTOR', 'ai', 'assert', 'base64', 'encoder', 'errorResponse', 'EXPIRY',
        'fixture', 'IMPORT', 'pasted', 'PNG', 'provider', 'rejects', 'request',
        'REQUEST', 'REVISION', 'SESSION', 'TEXT', 'token'])
    + '\n'
)
POLICY_IMPORTS = (
    COMMON
    + named_import('../_shared/roster_ai_dispatch_test_fixture.ts', [
        'SYNTHETIC_ROSTER_AI_CONFIGURATION', 'syntheticRosterAiApproval'])
    + named_import('./handler_test_fixture.ts', [
        'ai', 'base64', 'type Call', 'errorResponse', 'fixture', 'pasted', 'PNG',
        'request', 'REQUEST', 'TEXT'])
    + '\n'
)
CHANGES = {
    'supabase/functions/prepare-roster-import/handler_test.ts': (CORE_IMPORTS + CORE).encode(),
    'supabase/functions/prepare-roster-import/handler_test_fixture.ts': FIXTURE.encode(),
    'supabase/functions/prepare-roster-import/ai_dispatch_policy_test.ts': (POLICY_IMPORTS + POLICY_CASES).encode(),
}
RUNNER = ROOT / 'scripts/tests/verify_roster_decoder.py'
RUNNER_BYTES = RUNNER.read_bytes()
RUNNER_TEXT = RUNNER_BYTES.decode()
OLD = " 'supabase/functions/prepare-roster-import/handler.ts','supabase/functions/prepare-roster-import/handler_test.ts',\n"
assert RUNNER_TEXT.count(OLD) == 1
RUNNER_TEXT = RUNNER_TEXT.replace(OLD, OLD + " 'supabase/functions/prepare-roster-import/handler_test_fixture.ts','supabase/functions/prepare-roster-import/ai_dispatch_policy_test.ts',\n")
OLD = "['supabase/functions/prepare-roster-import/handler_test.ts','scripts/tests/roster_extraction_evaluation_test.ts']"
assert RUNNER_TEXT.count(OLD) == 1
RUNNER_TEXT = RUNNER_TEXT.replace(OLD, "['supabase/functions/prepare-roster-import/handler_test.ts','supabase/functions/prepare-roster-import/ai_dispatch_policy_test.ts','scripts/tests/roster_extraction_evaluation_test.ts']")
CHANGES['scripts/tests/verify_roster_decoder.py'] = RUNNER_TEXT.encode()

CLOSURE = {}
PENDING = [ORIGINAL]
while PENDING:
    path = PENDING.pop()
    relative = str(path.relative_to(ROOT))
    if relative in CLOSURE:
        continue
    body = path.read_bytes()
    CLOSURE[relative] = body
    for declaration in re.findall(r'^import\b[\s\S]*?;', body.decode(), re.MULTILINE):
        match = re.search(r'["\']([^"\']+)["\']\s*;\s*$', declaration)
        assert match, declaration
        spec = match.group(1)
        assert spec.startswith('.'), 'Unexpected remote dependency: ' + spec
        target = (path.parent / spec).resolve(strict=True)
        assert target.is_relative_to(ROOT)
        PENDING.append(target)
for relative in ['supabase/functions/deno.lock', '.dvmrc']:
    CLOSURE[relative] = (ROOT / relative).read_bytes()
CLOSURE['scripts/tests/verify_roster_decoder.py'] = RUNNER_BYTES
for kind in ('baseline', 'candidate'):
    assert not (OUT / kind).exists()
    for relative, body in CLOSURE.items():
        target = OUT / kind / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    if kind == 'candidate':
        for relative, body in CHANGES.items():
            target = OUT / kind / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(body)


def info(body):
    return {'sha256': hashlib.sha256(body).hexdigest(), 'bytes': len(body), 'lines': len(body.splitlines())}


SUMMARY = {
    'scope': 'Shared handler fixture plus existing AI dispatch policy capability; explicit Linux regression/source inventory additions only',
    'before': {k: info(v) for k, v in CLOSURE.items()},
    'proposed': {k: info(v) for k, v in CHANGES.items()},
    'exact_preserved_segments': {
        'core_registration_blocks': info(CORE.encode()),
        'ai_policy_registration_blocks_and_helpers': info(POLICY_CASES.encode()),
        'shared_fixture_declarations': info(HELPERS.encode()),
    },
    'handler_unchanged': True,
    'runtime_test_completion_pending': True,
    'maintained_mutation': False,
}
(OUT / 'proposal.json').write_text(json.dumps(SUMMARY, indent=2) + '\n')
print(json.dumps({'closure_files': len(CLOSURE), 'changes': SUMMARY['proposed']}, indent=2))
