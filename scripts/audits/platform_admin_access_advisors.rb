# Read-only pinned Supabase SQL advisor for the exact platform UAT sandbox.
require 'json'
require 'open3'
require 'digest'
require 'time'
DB = 'collect_platform_access_uat_20260902'.freeze
SOURCE = 'https://raw.githubusercontent.com/supabase/cli/v2.101.0/apps/cli-go/internal/db/advisors/templates/lints.sql'.freeze
sql,err,status=Open3.capture3('curl','--fail','--silent','--show-error','--max-time','20',SOURCE)
abort(err) unless status.success?
abort('Pinned query changed') unless Digest::SHA256.hexdigest(sql)=='4566342793150742ca7bf539295d4175af4218761925927190fdec31315ae15c'
setup,query=sql.split(";\n\n",2)
abort('Unexpected query format') unless setup=="set local search_path = ''" && query&.lstrip&.start_with?('(')
raw,err,status=Open3.capture3('docker','inspect','collect_platform_access_api_20260902')
abort(err) unless status.success?
settings=JSON.parse(raw).first.fetch('Config').fetch('Env').to_h{|entry|entry.split('=',2)}
abort('Unexpected API schema') unless settings.fetch('PGRST_DB_SCHEMAS')=='public'
abort('Unexpected database') unless settings.fetch('PGRST_DB_URI').end_with?('/'+DB)
out,err,status=Open3.capture3('docker','exec','-i','supabase_db_collect','psql','-XqAt','-U','postgres','-d',DB,'-v','ON_ERROR_STOP=1',stdin_data:<<~SQL)
  begin read only;
  set local statement_timeout='30s';
  set local pgrst.db_schemas='public';
  #{setup};
  select coalesce(jsonb_agg(to_jsonb(lint)),'[]'::jsonb) from (#{query.strip.sub(/;\z/,'')})lint;
  rollback;
SQL
abort(err) unless status.success?
rows=JSON.parse(out)
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,database:DB,mode:'read-only pinned SQL, not hosted or independent security certification',
  source:SOURCE,source_sha256:Digest::SHA256.hexdigest(sql),counts:rows.group_by{|row|row['level']}.transform_values(&:length),results:rows)
exit(rows.any?{|row|%w[WARN ERROR].include?(row['level'])} ? 1 : 0)
