begin;
grant usage on schema graphql,graphql_public to postgres,anon,authenticated,service_role;
grant usage on schema graphql,graphql_public to postgres with grant option;
grant execute on function graphql._internal_resolve(text,jsonb,text,jsonb),graphql.comment_directive(text),graphql.exception(text),graphql.get_schema_version(),graphql.increment_schema_version(),graphql.resolve(text,jsonb,text,jsonb) to postgres,anon,authenticated,service_role;
grant select,update,usage on sequence graphql.seq_schema_version to postgres,anon,authenticated,service_role;
create index if not exists collect_receipt_http_response_id on net._http_response(id);
commit;
