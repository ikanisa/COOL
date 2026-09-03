require 'open3'
require 'json'
require 'digest'
require 'time'

# Never accepts a database URL or container argument. Supabase CLI must have
# initialized this separate, empty application environment first.
current_release = !!ARGV.delete('--current-release')
container = current_release ? 'supabase_db_collect_release_replay_20260902' : 'supabase_db_collect_clean_uat_20260902'
abort('Unknown argument') unless ARGV.empty? || ARGV==['--with-synthetic-owner']
synthetic_owner=ARGV==['--with-synthetic-owner']
command=['docker','exec','-i',container,'psql','-XqAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']
def execute(command,sql)
  Open3.capture3(*command,stdin_data:sql)
end
guard=<<~SQL
  do $$ begin
    if to_regclass('public.profiles') is not null or exists(select 1 from auth.users) then
      raise exception 'Empty Collect application and Auth accounts required';
    end if;
  end $$;
  select current_setting('server_version');
SQL
out,err,status=execute(command,guard)
abort(err) unless status.success?
server_version=out.strip
# This isolated rehearsal must not launch scheduled reconciliation jobs.
platform_command=['docker','exec','-i',container,'sh','-c',
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -XqAt -U supabase_admin -d postgres -v ON_ERROR_STOP=1']
out,err,status=execute(platform_command,"alter system set cron.launch_active_jobs='off'; select pg_reload_conf();")
abort(err) unless status.success?
out,err,status=execute(command,<<~SQL)
  create schema if not exists supabase_migrations;
  create table if not exists supabase_migrations.schema_migrations(
    version text primary key,statements text[],name text);
SQL
abort(err) unless status.success?
results=[]
Dir[File.expand_path('../../supabase/migrations/*.sql',__dir__)].sort.each do |path|
  sql=File.read(path)
  version,name=File.basename(path,'.sql').split('_',2)
  if synthetic_owner && version=='20260901134820'
    out,err,status=execute(command,<<~SQL)
      begin;
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
      values('99100000-0000-4000-8000-000000000001','authenticated','authenticated','250788991001',now(),'{}','{}');
      update public.profiles set is_platform_admin=true where id='99100000-0000-4000-8000-000000000001';
      commit;
    SQL
    abort(err) unless status.success?
  end
  started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out,err,status=execute(command,sql)
  result={migration:File.basename(path),sha256:Digest::SHA256.hexdigest(sql),
    status:status.success? ? 'pass' : 'fail',seconds:(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(3)}
  results << result
  unless status.success?
    result[:error]=err.lines.grep(/ERROR|DETAIL|CONTEXT|LINE/).join.strip
    break
  end
  _,err,status=execute(command,"insert into supabase_migrations.schema_migrations(version,name,statements) values ('#{version}','#{name}',array['Clean isolated replay']);")
  abort(err) unless status.success?
end
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,container:container,
  mode:'clean Supabase CLI platform bootstrap; all application migrations replayed; no customer data or provider calls',
  server_version:server_version,cron_launch_active_jobs:false,synthetic_bootstrap_owner:synthetic_owner,migrations:results,
  status:results.length>0 && results.all?{|r|r[:status]=='pass'} ? 'pass' : 'fail')
exit(results.length>0 && results.all?{|r|r[:status]=='pass'} ? 0 : 1)
