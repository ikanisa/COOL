require 'open3'

# Reuse the guarded, rollback-only mixed-rail 21,000-payment fixture.
sql = File.read(__dir__+'/member_volume_uat.sql')
sql = sql.sub("select 'MEMBER_VOLUME_UAT_PASS';", <<~SQL)
  do $$ declare first_page jsonb; page jsonb; cursor_value jsonb; all_rows jsonb := '[]';
    pages integer := 0; started timestamptz; query_sort text;
  begin
    started=clock_timestamp();
    first_page=public.list_current_member_history_page();
    raise notice 'PAGINATION_FIRST_PAGE %', jsonb_build_object(
      'server_ms',round(extract(epoch from clock_timestamp()-started)*1000,3),
      'bytes',octet_length(first_page::text),'rows',jsonb_array_length(first_page->'items'),
      'total_count',first_page->'total_count');
    perform pg_temp.assert_true(jsonb_array_length(first_page->'items')=50 and
      first_page->>'total_count'='11000','bounded first page with complete count');
    perform pg_temp.assert_true(first_page->'totals'='{"EUR":12345000,"RWF":10000000}'::jsonb
      and first_page->'own_totals'='{"EUR":12345,"RWF":10000}'::jsonb,
      'complete per-currency totals, not page totals');
    page=public.list_current_member_history_page(p_limit=>100);
    loop
      pages=pages+1;
      perform pg_temp.assert_true(jsonb_array_length(page->'items') between 1 and 100,
        'every page bounded');
      perform pg_temp.assert_true(page->'revision'=first_page->'revision' and
        page->'totals'=first_page->'totals','same revision and aggregates');
      all_rows=all_rows||(page->'items');
      cursor_value=page->'next_cursor';
      exit when cursor_value='null'::jsonb;
      perform pg_temp.assert_true(pages<111,'finite progress');
      page=public.list_current_member_history_page(p_cursor=>cursor_value,p_limit=>100);
    end loop;
    perform pg_temp.assert_true(all_rows=public.list_current_member_payment_history(),
      'all pages equal complete legacy history exactly, including tied timestamps and privacy');
    raise notice 'PAGINATION_ALL_PAGES %',jsonb_build_object('pages',pages,
      'rows',jsonb_array_length(all_rows),'total_ms',round(extract(epoch from clock_timestamp()-started)*1000,3));
    page=public.list_current_member_history_page(p_query=>'VOLUME-MOMO-9002');
    perform pg_temp.assert_true(page->>'total_count'='1' and
      page->'items'->0->>'transaction_id'='VOLUME-MOMO-9002','search beyond first page');
    page=public.list_current_member_history_page(p_query=>'VOLUME-MOMO-9003');
    perform pg_temp.assert_true(page->>'total_count'='0','search cannot disclose private peer references');
    page=public.list_current_member_history_page(p_query=>'SYNTHETIC VOLUME VISIBLE');
    perform pg_temp.assert_true(page->>'total_count'='11000','case-insensitive group search');
    page=public.list_current_member_history_page(p_collection_id=>'98000000-0000-4000-8000-000000020000');
    perform pg_temp.assert_true(page->>'total_count'='0','foreign private group remains invisible');
    foreach query_sort in array array['oldest','highest','lowest'] loop
      page=public.list_current_member_history_page(p_sort=>query_sort,p_limit=>1);
      if query_sort='oldest' then
        perform pg_temp.assert_true(page->'items'->0->>'payment_id'='momo:98000001-0000-4000-8000-000000010000','oldest sort');
      else
        perform pg_temp.assert_true(page->'items'->0->>'currency'='EUR','amount sorts never compare cents with francs');
      end if;
      begin
        perform public.list_current_member_history_page(p_sort=>query_sort,p_cursor=>first_page->'next_cursor');
        raise exception 'FAIL: accepted cursor for different sort';
      exception when sqlstate 'P0001' then
        if sqlerrm like 'FAIL:%' then raise; end if;
      end;
    end loop;
    begin perform public.list_current_member_history_page(p_limit=>101);
      raise exception 'FAIL: unbounded limit accepted'; exception when invalid_parameter_value then null; end;
    begin perform public.list_current_member_history_page(p_cursor=>'{}');
      raise exception 'FAIL: malformed cursor accepted'; exception when invalid_parameter_value then null; end;
    page=public.list_current_member_recent_intents();
    perform pg_temp.assert_true(jsonb_array_length(page->'items')=50 and page->>'pending_count'='0',
      'bounded recent intents and accurate pending count');
    page=public.list_current_member_recent_intents('98000004-0000-4000-8000-000000001000');
    perform pg_temp.assert_true(jsonb_array_length(page->'items')=1 and page->'items'->0->>'status'='expired',
      'old deep-linked intent still resolves');
    page=public.list_current_member_recent_intents('98000002-0000-4000-8000-000000000003');
    perform pg_temp.assert_true(page->'items'='[]'::jsonb,'foreign intent not exposed');
    perform set_config('request.jwt.claims','{}',true);
    begin perform public.list_current_member_history_page();
      raise exception 'FAIL: missing identity accepted'; exception when invalid_authorization_specification then null; end;
    perform set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
    begin perform public.list_current_member_history_page(p_cursor=>first_page->'next_cursor');
      raise exception 'FAIL: cross-account cursor accepted'; exception when sqlstate 'P0001' then
        if sqlerrm like 'FAIL:%' then raise; end if; end;
  end $$;
  select 'MEMBER_PAGINATION_UAT_PASS';
SQL
out,err,status = Open3.capture3('docker','exec','-i','supabase_db_collect','psql','-XqAt','-U','postgres',
  '-d','collect_uat_20260902','-v','ON_ERROR_STOP=1',stdin_data:sql)
puts out
warn err
exit(status.exitstatus)
