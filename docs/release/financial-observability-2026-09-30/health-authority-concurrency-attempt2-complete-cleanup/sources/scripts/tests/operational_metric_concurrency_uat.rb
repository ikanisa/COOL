require_relative 'runtime_control_concurrency_uat'
require 'time'

# Root-owned exact148 fixture. Only fixed-code telemetry rows are created;
# committed cleanup requires observed transaction attribution and empty baseline.
HEALTH_MIGRATION='supabase/migrations/20260930160000_redacted_operational_health.sql'
METRIC_TABLE='collect_security.operational_metric_buckets'
def health_service
 "set local role service_role; select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
end
def health_write(w,code,duration,marker)
 start(w,health_service+"select 'RESULT:'||public.record_operational_metric_v1(#{lit(code)},#{duration.nil? ? 'null' : duration})::text; select '#{marker}';")
end
def health_finish(w,command,marker)
 # psql consumes a complete input line. Without this newline it waits for
 # another command while the peer remains blocked on the open transaction.
 write(w,"#{command}; reset role; select '#{marker}';\n")
 read_until(w,marker)
end
def health_row(w,code,marker)
 write(w,"reset role; select 'METRIC:'||jsonb_build_object('events',sum(event_count),'measured',sum(measured_count),'total_ms',sum(duration_total_ms),'max_ms',max(duration_max_ms))::text from #{METRIC_TABLE} where event_code=#{lit(code)}; select '#{marker}';\n")
 line=read_until(w,marker).find {|s|s.start_with?('METRIC:')};raise 'Missing actual metric aggregation' unless line
 JSON.parse(line.delete_prefix('METRIC:'))
end
def health_clean
 rows=JSON.parse(query("select coalesce(jsonb_agg(jsonb_build_object('xmin',xmin::text,'code',event_code,'bucket',bucket_at,'events',event_count,'measured',measured_count,'duration',duration_total_ms,'max',duration_max_ms)),'[]') from #{METRIC_TABLE};"))
 raise 'Unattributed telemetry row; preserve fixture' unless rows.all? {|r|TRACKED_XIDS.include?(r['xmin'])}
 query("delete from #{METRIC_TABLE} where xmin::text in (#{TRACKED_XIDS.map {|x|lit(x)}.join(',')});",transaction:true) unless rows.empty?
 raise 'Metric baseline not restored' unless query("select count(*) from #{METRIC_TABLE};")=='0'
 rows.map {|r|r.reject {|k,_|k=='bucket'}}
end
def health_clock_window
 # The production function chooses a real minute; do not simulate its clock.
 # Avoid crossing a minute while proving same-key blocking, without changing it.
 25.times do
  return if query("select extract(second from clock_timestamp())::int;").to_i<=40
  sleep 1
 end
 raise 'Could not obtain a bounded real-clock concurrency window'
end

if __FILE__==$PROGRAM_NAME
 raise 'Explicit root fixture authorization required' unless ENV['COLLECT_OPERATIONAL_METRICS_QA']=='isolated_clone'
 raise 'New absolute checkpoint required' unless CHECKPOINT_PATH && CHECKPOINT_PATH.start_with?('/') && !File.exist?(CHECKPOINT_PATH)
 reviewed=ENV.fetch('COLLECT_OPERATIONAL_HEALTH_SHA','')
 raise 'Exact reviewed148 source required' unless reviewed.match?(/\A[a-f0-9]{64}\z/) && Digest::SHA256.file(File.join(ROOT,HEALTH_MIGRATION)).hexdigest==reviewed
 raw,error,success=Open3.capture3('docker','inspect',CONTAINER);raise error unless success.success?
 c=JSON.parse(raw).first;labels=c.fetch('Config').fetch('Labels');ports=c.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
 raise 'Exact owned running fixture/port required' unless c.dig('State','Running') && labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT && ports.all? {|p|p['HostPort']=='55722'}
 query(<<~SQL)
  do $$ begin
   if current_user<>'postgres' or current_database()<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>148 or (select max(version) from supabase_migrations.schema_migrations)<>'20260930160000'
    or exists(select 1 from #{METRIC_TABLE})
    or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930160000')<>#{lit(reviewed)} then
    raise exception 'Exact quiet148 empty telemetry baseline required';end if;
  end $$;
 SQL
 tables=snapshot_tables;before=JSON.parse(query(fingerprints_sql(tables)));controls=query(controls_sql)
 CHECKPOINT.merge!({'kind'=>'actual148_metric_concurrency','started_at'=>Time.now.utc.iso8601,'before'=>before,'controls_before'=>controls,'source_sha256'=>reviewed});save_checkpoint
 workers=[];cases=[];failure=nil
 begin
  a=worker_start('collect_health148_a',workers);b=worker_start('collect_health148_b',workers)
  code='receipt_ack_generated'

  health_clock_window
  health_write(a,code,10,'A_WRITE');read_until(a,'A_WRITE')
  health_write(b,code,20,'B_WRITE');wait=blocked(b,a)
  health_finish(a,'rollback','A_ROLLBACK');read_until(b,'B_WRITE')
  row=health_row(b,code,'B_ROW');raise 'Rolled-back holder contributed a false metric' unless row=={'events'=>1,'measured'=>1,'total_ms'=>20,'max_ms'=>20}
  health_finish(b,'rollback','B_ROLLBACK');health_clean
  cases<<{name:'holder_rollback_waiter_records_once',status:'pass',blocking:wait,observed:row}

  health_clock_window
  health_write(a,code,10,'A_WRITE');read_until(a,'A_WRITE')
  health_write(b,code,nil,'B_WRITE');wait=blocked(b,a)
  health_finish(a,'commit','A_COMMIT');read_until(b,'B_WRITE')
  row=health_row(b,code,'B_ROW');raise 'Unmeasured event changed measured denominator' unless row=={'events'=>2,'measured'=>1,'total_ms'=>10,'max_ms'=>10}
  health_finish(b,'rollback','B_ROLLBACK');attribution=health_clean
  raise 'Committed holder was not durable' unless attribution.length==1 && attribution[0]['events']==1
  cases<<{name:'commit_then_unmeasured_waiter_rollback',status:'pass',blocking:wait,observed:row,cleanup_attribution:attribution}

  health_clock_window
  health_write(a,code,10,'A_WRITE');read_until(a,'A_WRITE')
  health_write(b,code,20,'B_WRITE');wait=blocked(b,a)
  health_finish(a,'commit','A_COMMIT');read_until(b,'B_WRITE')
  row=health_row(b,code,'B_ROW');raise 'Concurrent increments lost a count/duration/max' unless row=={'events'=>2,'measured'=>2,'total_ms'=>30,'max_ms'=>20}
  health_finish(b,'commit','B_COMMIT');attribution=health_clean
  raise 'Combined committed result was not durable' unless attribution.length==1 && attribution[0]['events']==2 && attribution[0]['duration']==30
  cases<<{name:'both_commits_preserve_count_duration_max',status:'pass',blocking:wait,observed:row,cleanup_attribution:attribution}

  health_clock_window
  health_write(a,code,10,'A_WRITE');read_until(a,'A_WRITE')
  health_write(b,'receipt_rejected',nil,'B_WRITE');read_until(b,'B_WRITE')
  blocked_by=JSON.parse(query("select to_json(pg_blocking_pids(#{b[:pid]}));"));raise 'Unrelated fixed codes serialized globally' unless blocked_by.empty?
  row=health_row(b,'receipt_rejected','B_ROW');raise 'Independent unmeasured event malformed' unless row=={'events'=>1,'measured'=>0,'total_ms'=>0,'max_ms'=>0}
  health_finish(a,'rollback','A_ROLLBACK');health_finish(b,'rollback','B_ROLLBACK');health_clean
  cases<<{name:'independent_codes_do_not_block',status:'pass',blocking_pids:blocked_by,observed:row}

  health_clock_window
  start(a,"insert into #{METRIC_TABLE}(bucket_at,event_code,event_count,measured_count,duration_total_ms,duration_max_ms) values(date_trunc('minute',clock_timestamp()),#{lit(code)},9007199254740991,0,0,0); select 'A_WRITE';")
  read_until(a,'A_WRITE')
  start(b,health_service+"do $$ declare denied boolean:=false;begin begin perform public.record_operational_metric_v1(#{lit(code)},null); exception when check_violation then denied:=true;end; if not denied then raise exception 'Unsafe integer overflow accepted';end if;end $$;select 'B_DENIED';")
  wait=blocked(b,a);health_finish(a,'commit','A_COMMIT');read_until(b,'B_DENIED')
  row=health_row(b,code,'B_ROW');raise 'Rejected overflow altered prior count' unless row=={'events'=>9007199254740991,'measured'=>0,'total_ms'=>0,'max_ms'=>0}
  health_finish(b,'rollback','B_ROLLBACK');attribution=health_clean
  cases<<{name:'concurrent_integer_limit_denies_without_corruption',status:'pass',blocking:wait,observed:row,cleanup_attribution:attribution}
 rescue Exception=>e
  failure={class:e.class.name,message:e.message};CHECKPOINT['failure']=failure;save_checkpoint
 ensure
  workers.each do |w|
   begin
    health_finish(w,'rollback','ROOT_CLOSED') if w[:thread].alive?
    w[:input].close unless w[:input].closed?
    Timeout.timeout(10) {w[:thread].value}
   rescue Exception=>e
    CHECKPOINT['worker_close_failure']={class:e.class.name,message:e.message};save_checkpoint
   end
  end
 end
 # Never invent restoration after a failure. Attributed fixed-code fixture rows
 # alone may be removed; all other application/Auth/cron tables must match.
 health_clean
 after=JSON.parse(query(fingerprints_sql(tables)));after_controls=query(controls_sql)
 count=query("select count(*) from pg_stat_activity where application_name in ('collect_health148_a','collect_health148_b');").to_i
 raise 'Full table/catalog restoration or worker termination failed' unless before==after && controls==after_controls && count==0
 CHECKPOINT.merge!({'status'=>failure ? 'fail' : 'pass','cases'=>cases,'cases_passed'=>cases.length,'blocking_races'=>cases.count {|x|x[:blocking]},'all_tables_restored'=>true,'all_controls_restored'=>true,'worker_sessions_remaining'=>count,'finished_at'=>Time.now.utc.iso8601,'source_only'=>false,'provider_called'=>false,'hosted_called'=>false});save_checkpoint
 puts JSON.pretty_generate(CHECKPOINT.reject {|k,_|k=='before'})
 raise failure[:message] if failure
 raise 'All five actual cases required' unless cases.length==5
end
