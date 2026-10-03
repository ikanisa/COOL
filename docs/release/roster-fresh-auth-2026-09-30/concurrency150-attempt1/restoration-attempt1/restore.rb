require 'json'
require 'digest'
require ARGV.fetch(0)
raise 'Reviewed harness source changed' unless Digest::SHA256.file(ARGV.fetch(0)).hexdigest==ARGV.fetch(2)
checkpoint=JSON.parse(File.read(ARGV.fetch(1)))
raise 'Retained exact failed cleanup packet required' unless checkpoint.fetch('phase')=='cleanup_failed' && checkpoint.fetch('fixture')==PROJECT && checkpoint.fetch('migration_count')==150 && checkpoint.fetch('migration_sha256')==MIGRATION_SHA && checkpoint.fetch('authority_migration_sha256')==AUTHORITY_SHA
CHECKPOINT.merge!(checkpoint)
raise 'Original catalog controls or table inventory changed' unless snapshot_tables==checkpoint.fetch('baseline_tables') && query(controls_sql+';')==checkpoint.fetch('controls_sha256')
raise 'Synthetic workers still present' unless query("select count(*) from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}');")=='0'
attribution=JSON.parse(query(owned_xids_sql+';'))
raise 'Owned synthetic row attribution changed' unless attribution==checkpoint.fetch('owned_row_xid_attribution')
xids=(checkpoint.fetch('tracked_transaction_ids')+attribution.map {|row|row.fetch('xmin')}).uniq
raise 'Missing or malformed XID evidence' if xids.empty? || xids.any? {|x|!x.match?(/\A[0-9]+\z/)}
triggers=CLEANUP_GUARDS.map {|table,name|"('#{table}'::regclass,'#{name}')"}.join(',')
guard=<<~SQL
 do $$ declare x record; begin for x in select * from (values #{triggers}) expected(relation,name) loop
  if (select count(*) from pg_trigger where tgrelid=x.relation and tgname=x.name and not tgisinternal and tgenabled='O')<>1
   or exists(select 1 from pg_trigger where tgrelid=x.relation and not tgisinternal and (tgtype::int & 2)=2 and (tgtype::int & 8)=8 and tgname<>x.name) then
   raise exception 'Unexpected cleanup trigger guard'; end if;
 end loop; end $$;
SQL
sql=cleanup_sql(tables:checkpoint.fetch('baseline_tables'),before:checkpoint.fetch('baseline_sha256'),controls:checkpoint.fetch('controls_sha256'),flag:checkpoint.fetch('feature_flag'),permission_rows:checkpoint.fetch('permission_rows'),xids:xids,trigger_guard:guard,fingerprints:checkpoint.fetch('baseline_fingerprints'),governance_heads:checkpoint.fetch('governance_heads'),baseline_event_ids:checkpoint.fetch('baseline_governance_event_ids'))
File.write(ARGV.fetch(3),sql)
query(sql,transaction:true)
raise 'Complete retained baseline not restored' unless query(digest_sql(checkpoint.fetch('baseline_tables'))+';')==checkpoint.fetch('baseline_sha256') && query(controls_sql+';')==checkpoint.fetch('controls_sha256')
puts JSON.generate(status:'pass',retained_checkpoint_unchanged:true,all_tables_and_controls_restored:true,tracked_xids:xids.length)
