// Test-only transformation: no database, network, credential or CLI access.
// The original candidate remains untouched. Output is NOT a production artifact.
import {createHash} from 'node:crypto';

export const ORIGINAL_SHA256='16e8d236686789397edbfe71f6e6a7e13367ba22c0fdfabf0ca322e03779bd65';
const hash=s=>createHash('sha256').update(s).digest('hex');
const originalGuard=` IF EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND pg_has_role(r.oid,'postgres'::regrole,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_owner_role_preimage';END IF;`;

// Caller must select a freshly created fixture and read its own PG catalogue.
// OIDs are not portable and must never be substituted for a fresh live preimage.
export function syntheticProviderBinder({source,trust,fixtureDatabase,oids}){
 if(trust!=='synthetic-provider-admin-is-trusted')throw new Error('synthetic_trust_assumption_required');
 if(typeof source!=='string'||hash(source)!==ORIGINAL_SHA256||source.split(originalGuard).length!==2)
  throw new Error('original_candidate_preimage_mismatch');
 if(!/^collect_managed_identity_[0-9a-f]{32}_test$/.test(fixtureDatabase??''))throw new Error('fixture_database_required');
 const keys=['owner','provider','cli','membership'];
 if(!oids||Object.keys(oids).sort().join(',')!==[...keys].sort().join(',')||
    keys.some(k=>!Number.isSafeInteger(oids[k])||oids[k]<1||oids[k]>4294967295)||
    new Set(keys.map(k=>oids[k])).size!==keys.length)throw new Error('invalid_fixture_oids');
 const {owner,provider,cli,membership}=oids;
 const fixtureGuard=`-- Synthetic-only guard. This does not qualify any hosted SQL execution.\nDO $fixture_only$ BEGIN
 IF current_database() IS DISTINCT FROM '${fixtureDatabase}' OR current_setting('cluster_name',true) IS DISTINCT FROM 'collect_managed_identity_synthetic_only'
  OR inet_server_addr() IS NOT NULL OR inet_client_addr() IS NOT NULL OR session_user <> 'postgres'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='SYNTHETIC_ONLY_REFUSAL'; END IF;
END $fixture_only$;\n`;
 const replacement=` -- Explicit trust boundary: the exact CLI role below may assume the owner.
 -- Its provider/admin issuer and any live sessions are trusted, not absent.
 IF NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${owner}::oid AND r.rolname='postgres'
    AND NOT r.rolsuper AND r.rolcanlogin AND r.rolbypassrls)
  OR NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${provider}::oid AND r.rolname='supabase_admin' AND r.rolsuper)
  OR NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${cli}::oid AND r.rolname='cli_login_postgres'
    AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolinherit AND NOT r.rolcreatedb
    AND NOT r.rolcreaterole AND NOT r.rolreplication AND NOT r.rolbypassrls AND r.rolconnlimit=-1)
  OR (SELECT count(*) FROM pg_auth_members m WHERE m.member=${cli}::oid)<>1
  OR NOT EXISTS(SELECT 1 FROM pg_auth_members m WHERE m.oid=${membership}::oid AND m.roleid=${owner}::oid
    AND m.member=${cli}::oid AND m.grantor=${provider}::oid AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option)
  OR EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.oid NOT IN(${owner}::oid,${cli}::oid)
    AND (pg_has_role(r.oid,${owner}::oid,'MEMBER') OR pg_has_role(r.oid,${cli}::oid,'MEMBER')))
  OR EXISTS(SELECT 1 FROM pg_roles r CROSS JOIN pg_roles s WHERE NOT r.rolsuper AND s.rolsuper
    AND pg_has_role(r.oid,s.oid,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_provider_role_preimage';END IF;`;
 return fixtureGuard+source.replace(originalGuard,replacement);
}

// An explicit hard stop rather than a hidden live-dispatch feature.
export function executeManaged(){throw new Error('managed_execution_not_implemented_or_authorized');}
