require 'open3'

# Compare the optimized API against the previous implementation in the same
# synthetic snapshot, in addition to the volume/privacy/balance assertions.
root = File.expand_path('../..', __dir__)
previous = File.read(root+'/supabase/migrations/20260902083940_member_cross_rail_history.sql')[
  /create function public\.list_current_member_payment_history\(\).*?end \$\$;/m
]
abort('Prior history definition unavailable') unless previous
previous = previous.sub('public.list_current_member_payment_history()', 'pg_temp.previous_member_history()')
sql = File.read(__dir__+'/member_volume_uat.sql')
sql = sql.sub('set local role authenticated;', previous+"\nset local role authenticated;")
sql = sql.sub("select 'MEMBER_VOLUME_UAT_PASS';", <<~SQL)
  select pg_temp.assert_true(public.list_current_member_payment_history()=pg_temp.previous_member_history(),
    'optimized and prior history responses identical in the same snapshot');
  select 'MEMBER_VOLUME_UAT_PASS_WITH_EXACT_EQUIVALENCE';
SQL
out,err,status = Open3.capture3('docker','exec','-i','supabase_db_collect','psql','-XqAt','-U','postgres',
  '-d','collect_uat_20260902','-v','ON_ERROR_STOP=1',stdin_data:sql)
puts out
warn err
exit(status.exitstatus)
