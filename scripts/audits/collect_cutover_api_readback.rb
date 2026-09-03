# Read-only public HTTP checks and owner-authorized SQL READ ONLY member
# contract checks. No real tokens are manufactured and no sessions are added.
require_relative 'collect_production_cutover'
require_relative 'collect_release_build'

module CollectCutoverApiReadback
  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    STDOUT.sync = true
    puts 'Awaiting readback credentials on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    input = JSON.parse(raw.to_s)
    raw.clear
    CollectReleaseBuild.environment(input)
    token = input.fetch('access_token')
    public_key = input.fetch('anon_key')
    report = {started_at:Time.now.utc.iso8601,project:CollectProductionCutover::REF,
      http_checks:[],provider_sends:0,auth_sessions_created:0,database_writes:0}
    tests = [
      ['public_runtime','/rest/v1/rpc/get_public_runtime_config',{},[200]],
      ['legacy_profile_denied','/rest/v1/rpc/get_current_profile',{},[401,403]],
      ['member_profile_anonymous_denied','/rest/v1/rpc/get_current_member_profile',{},[401,403]],
      ['profile_names_anonymous_denied','/rest/v1/profiles?select=display_name&limit=1',nil,[401,403]],
      ['receipt_ingestion_anonymous_denied','/functions/v1/ingest-payment-sms',{},[401,403]],
      ['receipt_parser_missing_internal_secret_denied','/functions/v1/parse-payment-sms',{},[401,403]]
    ]
    tests.each do |label,path,payload,expected|
      uri = URI(input.fetch('project_url')+path)
      req = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req['apikey'] = public_key
      req['Authorization'] = "Bearer #{public_key}"
      if payload
        req['Content-Type']='application/json'
        req.body=JSON.generate(payload)
      end
      http = Net::HTTP.new(uri.host,443)
      http.use_ssl=true
      http.open_timeout=15
      http.read_timeout=30
      response=http.request(req)
      passed=expected.include?(response.code.to_i)
      report[:http_checks] << {check:label,http_status:response.code.to_i,pass:passed}
      raise "HTTP contract failed: #{label}" unless passed
      puts "PASS #{label} (#{response.code})"
    end
    # Authorization is simulated only within a read-only SQL transaction; this
    # does not stand in for real fresh-sign-in HTTP/provider UAT.
    sql = <<~SQL
      DO $member_readback$
      DECLARE r record; payload jsonb; page jsonb; keys text[]; checked integer:=0;
      BEGIN
        FOR r IN SELECT id,public_id FROM public.profiles ORDER BY id LOOP
          PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r.id,'role','authenticated')::text,true);
          SET LOCAL ROLE authenticated;
          payload:=public.get_current_member_profile();
          SELECT array_agg(key ORDER BY key) INTO keys FROM jsonb_object_keys(payload) key;
          IF keys IS DISTINCT FROM ARRAY['country_code','currency_code','id','momo_number','momo_provider','public_id','revolut_account','revolut_link','whatsapp_phone']
             OR payload->>'public_id' IS DISTINCT FROM r.public_id::text THEN
            RAISE EXCEPTION 'Name-free member profile contract failed';
          END IF;
          page:=public.list_current_member_history_page();
          IF jsonb_typeof(page->'items') IS DISTINCT FROM 'array'
             OR jsonb_typeof(page->'totals') IS DISTINCT FROM 'object'
             OR (page->>'total_count')::integer IS DISTINCT FROM jsonb_array_length(public.list_current_member_payment_history())
             OR jsonb_typeof(public.list_current_member_recent_intents()->'items') IS DISTINCT FROM 'array'
             OR jsonb_typeof(public.list_current_member_collection_balances()) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'Member history contract failed';
          END IF;
          IF public.has_admin_permission('overview.read') THEN RAISE EXCEPTION 'Sessionless identity gained Admin access'; END IF;
          RESET ROLE;
          checked:=checked+1;
        END LOOP;
        IF checked=0 THEN RAISE EXCEPTION 'No existing profiles checked'; END IF;
      END $member_readback$;
      SELECT count(*) AS existing_profiles_checked FROM public.profiles;
    SQL
    rows = CollectProductionCutover.catalog_query(token,sql)
    report[:database_member_contracts] = {status:'pass',profiles_checked:rows.first.fetch('existing_profiles_checked'),
      transaction:'READ ONLY / ROLLBACK',real_authentication_session:false}
    report[:result]='PUBLIC_HTTP_AND_READ_ONLY_MEMBER_CONTRACTS_PASS'
    report[:finished_at]=Time.now.utc.iso8601
    File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(report)+"\n") }
    puts JSON.generate(report:output,result:report[:result])
  ensure
    raw&.clear
    token&.clear
    public_key&.clear
    input&.clear
  end
end

CollectCutoverApiReadback.run(ARGV.fetch(0)) if $PROGRAM_NAME==__FILE__
