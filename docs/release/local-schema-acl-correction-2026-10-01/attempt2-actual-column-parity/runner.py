#!/usr/bin/env python3
"""Prove exact API column privileges in a schema-only local154 clone.

No source rows, secrets, provider work or external database are used. Effective
permissions and explicit grant options are compared for every application and
Auth column, with real allowed/denied zero-row SQL probes.
"""
import argparse
import datetime
import json
from pathlib import Path

import local_schema_uat as local

R, U, ROOT = local.R, local.U, local.ROOT


def columns(db):
    names = ','.join(R.literal(name) for name in R.SCHEMAS)
    return json.loads(U.psql(db, f"""select jsonb_object_agg(identity,properties) from (
      select format('%I.%I.%I',n.nspname,c.relname,a.attname) identity,
        jsonb_build_object('explicit_api_acl',coalesce((
          select jsonb_agg(jsonb_build_object('role',coalesce(r.rolname,'PUBLIC'),
            'privilege',x.privilege_type,'grantable',x.is_grantable)
            order by coalesce(r.rolname,'PUBLIC'),x.privilege_type,x.is_grantable)
          from aclexplode(a.attacl)x left join pg_roles r on r.oid=x.grantee
          where x.grantee=0 or r.rolname in('anon','authenticated','service_role')),'[]'::jsonb),
          'effective_api_privileges',(select jsonb_object_agg(role,privileges) from (
            select role,jsonb_build_object(
              'SELECT',has_column_privilege(role,c.oid,a.attnum,'SELECT'),
              'INSERT',has_column_privilege(role,c.oid,a.attnum,'INSERT'),
              'UPDATE',has_column_privilege(role,c.oid,a.attnum,'UPDATE'),
              'REFERENCES',has_column_privilege(role,c.oid,a.attnum,'REFERENCES')) privileges
            from unnest(array['anon','authenticated','service_role'])role)s)) properties
      from pg_attribute a join pg_class c on c.oid=a.attrelid
        join pg_namespace n on n.oid=c.relnamespace
      where n.nspname in ({names}) and c.relkind in('r','p','v','m')
        and a.attnum>0 and not a.attisdropped
    )s;""").stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT/'docs/release'):
        parser.error('Fresh release evidence directory required')
    report.mkdir(parents=True,mode=0o700)
    source = Path(__file__).read_bytes()
    (report/'runner.py').write_bytes(source)
    evidence = dict(kind='actual_schema_clone_api_column_acl_parity',status='running',cases=[],
        started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        shared_source_written=False,source_rows_copied=False,provider_called=False)
    U.SQL_LOG = report/'queries.log'

    def check(name,ok,detail):
        evidence['cases'].append(dict(name=name,status='pass' if ok else 'failed',detail=detail))
        R.save(report/'result.json',evidence)
        print(('PASS ' if ok else 'FAIL ')+name,flush=True)
        if not ok:
            raise RuntimeError(name)

    try:
        with local.isolated(report,evidence,count=154,latest='20260930230000') as db:
            original,copied = columns('postgres'),columns(db)
            R.save(report/'source-column-privileges.json',original)
            R.save(report/'clone-column-privileges.json',copied)
            check('every column preserves explicit PUBLIC/API grants and all effective API privileges',
                original == copied,dict(columns=len(original),changed=[key for key in original
                    if original[key] != copied.get(key)],source_only=sorted(set(original)-set(copied)),
                    clone_only=sorted(set(copied)-set(original))))
            check('source selected-column contracts are exercised rather than an empty ACL fixture',
                sum(bool(value['explicit_api_acl']) for value in original.values()) >= 30,
                dict(columns_with_explicit_api_acl=sum(bool(value['explicit_api_acl']) for value in original.values())))
            for role in ('anon','authenticated'):
                allowed = U.psql(db,f'begin;set local role {role};select id,public_id from public.profiles limit 0;rollback;',False)
                check(role+' actually reads the permitted profile columns',allowed.returncode == 0,
                      dict(exit_code=allowed.returncode))
                denied = U.psql(db,f'begin;set local role {role};select raw_body from public.raw_payment_sms limit 0;rollback;',False)
                check(role+' cannot read private raw SMS even with zero rows',
                      denied.returncode != 0 and '42501:' in denied.stderr,dict(exit_code=denied.returncode))
            check('current recorder and runner source remains bound',Path(__file__).read_bytes() == source,{})
        evidence['status'] = 'pass'
    except Exception as error:
        evidence.update(status='failed',failure=str(error))
        raise
    finally:
        U.SQL_LOG = None
        evidence['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        R.save(report/'result.json',evidence)


if __name__ == '__main__':
    main()
