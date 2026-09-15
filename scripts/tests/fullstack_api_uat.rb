# frozen_string_literal: true

require_relative '../qa/fullstack_database_http'

# Current-schema HTTP authorization and persisted-effect review. Every mutation
# is confined to the one newly created database in FullstackDatabaseHttp.
class FullstackApiUat
  IDS = (1..8).map { |n| "98500000-0000-4000-8000-#{n.to_s.rjust(12, '0')}" }.freeze
  GROUPS = (100..102).map { |n| "98520000-0000-4000-8000-#{n.to_s.rjust(12, '0')}" }.freeze

  def initialize(directory)
    @session = FullstackDatabaseHttp::Session.new(directory)
    @session.report[:checks] = []
    @sources = %w[scripts/qa/fullstack_database.rb scripts/qa/fullstack_database_sql.rb
                  scripts/qa/fullstack_database_http.rb scripts/tests/fullstack_api_uat.rb]
    @session.report[:runner_sources] = hashes
    snapshots = File.join(directory, 'source-snapshots')
    Dir.mkdir(snapshots, 0o700)
    @sources.each { |source| FileUtils.cp(source, File.join(snapshots, File.basename(source))) }
  end

  def hashes
    @sources.to_h { |source| [source, Digest::SHA256.file(source).hexdigest] }
  end

  def session_id(n)
    "98510000-0000-4000-8000-#{n.to_s.rjust(12, '0')}"
  end

  def claims(n, **overrides)
    { sub: IDS.fetch(n-1), role: 'authenticated', aud: 'authenticated',
      iat: Time.now.to_i, exp: Time.now.to_i + 600, session_id: session_id(n),
      user_metadata: { role: 'platform_owner', is_platform_admin: true },
      app_metadata: { role: 'platform_owner' } }.merge(overrides)
  end

  def token(n, **overrides)
    @session.token(claims(n, **overrides))
  end

  def rpc(label, name, params = nil, as: 1, jwt: nil, **named_params)
    @session.request(label, '/rpc/'+name, body: params || named_params, jwt: jwt || (as && token(as)))
  end

  def check(label, condition, status = nil)
    @session.report[:checks] << { label: label, status: condition ? 'pass' : 'fail', http_status: status }
    @session.record!
    raise "FAIL #{label} (HTTP #{status})" unless condition
  end

  def denied(label, result, anonymous: false)
    status, data = result
    sql_denied = status == (anonymous ? 401 : 403) && data.is_a?(Hash) && data['code'] == '42501'
    # The original assert_admin_permission raises P0001. Require its exact
    # permission message, not any HTTP 400 or parameter/SQL error.
    legacy_admin_denied = !anonymous && status == 400 && data.is_a?(Hash) && data['code'] == 'P0001' &&
      data['message'].to_s.match?(/\AAdmin permission [a-z_]+\.[a-z_]+ required\z/)
    check(label, sql_denied || legacy_admin_denied, status)
  end

  def seed!
    output = @session.sql(<<~SQL, label: 'seed-fixtures')
      begin;
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
      select ('98500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
        'authenticated','authenticated','25078898500'||n,now(),'{}','{}' from generate_series(1,8)n;
      insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
      values('#{IDS[0]}','+250788985001','Synthetic HTTP initial approved operator');
      insert into public.admin_user_roles(user_id,role_id,reason)
      select '#{IDS[0]}',id,'Synthetic HTTP initial role' from public.admin_roles where name='platform_owner';
      insert into auth.sessions(id,user_id,created_at)
      select ('98510000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
        ('98500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp() from generate_series(1,8)n;
      insert into public.collections(id,slug,creator_user_id,title,visibility,public_status)
      values ('#{GROUPS[0]}','http-roster-public','#{IDS[3]}','Synthetic HTTP public','public_approved','public_approved'),
             ('#{GROUPS[1]}','http-roster-private','#{IDS[3]}','Synthetic HTTP private','private','private'),
             ('#{GROUPS[2]}','http-roster-other-owner','#{IDS[6]}','Synthetic other owner','private','private');
      insert into public.collection_members(collection_id,user_id,role,status)
      select g::uuid,u::uuid,'member',s::public.member_status
      from unnest(array['#{GROUPS[0]}','#{GROUPS[1]}'])g
      cross join (values('#{IDS[4]}','active'),('#{IDS[5]}','left'),('#{IDS[7]}','invited'))fixture(u,s);
      commit;
      select json_object_agg(id,public_id) from public.profiles where id in ('#{IDS.join("','")}');
    SQL
    @public_ids = JSON.parse(output.lines.last)
    @session.report[:synthetic_public_ids] = @public_ids
  end

  def admin!
    ready = false
    30.times do |attempt|
      begin
        code, data = rpc("readiness-#{attempt+1}", 'admin_current_user')
        if code == 200 && data.is_a?(Hash) && data['user_id'] == IDS[0]
          ready = true
          break
        end
      rescue IOError, EOFError, SystemCallError, FullstackDatabase::CommandTimeout
        # Each attempt is retained; readiness must eventually prove the actor.
      end
      sleep 0.2
    end
    check('approved live synthetic session reaches Admin', ready)

    code, data = rpc('legacy-list-signature', 'admin_list_admin_users', { p_search: @public_ids.fetch(IDS[0]), p_status: 'active' })
    check('two-argument Admin list resolves and finds exact operator', code == 200 && data['total'] == 1 && data['rows'].first['id'] == IDS[0], code)
    {
      'forged metadata on ordinary member' => token(3),
      'missing session ID' => token(1, session_id: nil),
      'malformed session ID' => token(1, session_id: 'not-a-uuid'),
      'another users session ID' => token(1, session_id: session_id(3))
    }.each do |label, jwt|
      code, data = rpc(label, 'admin_current_user', jwt: jwt)
      check(label+' yields no Admin identity', code == 200 && data == {}, code)
      denied(label+' denied protected detail', rpc(label+' protected', 'admin_get_admin_user', { p_id: IDS[1] }, jwt: jwt))
    end
    {
      'invalid JWT signature' => @session.token(claims(1), secret: 'different-synthetic-secret'),
      'expired JWT' => token(1, exp: Time.now.to_i - 120),
      'future not-before JWT' => token(1, nbf: Time.now.to_i + 600),
      'malformed JWT' => 'not-a-jwt'
    }.each do |label, jwt|
      code, data = rpc(label, 'admin_current_user', jwt: jwt)
      check(label+' rejected by API', code == 401 && data.is_a?(Hash) && data['code'].to_s.start_with?('PGRST'), code)
    end
    code, data = rpc('approval-read-before', 'admin_get_whatsapp_approval', { p_user_id: IDS[1] })
    check('approval status masks number and starts unapproved', code == 200 && data['approved'] == false &&
      data['role_granted'] == false && data['phone_masked'] == '+***5002', code)
    %w[admin_approve_whatsapp admin_revoke_whatsapp_approval admin_set_user_access].each do |name|
      params = { p_user_id: IDS[1], p_reason: 'Synthetic denied request' }
      params[:p_whatsapp_phone] = '+250788985002' if name == 'admin_approve_whatsapp'
      params[:p_active] = true if name == 'admin_set_user_access'
      [nil, 3].each do |actor|
        label = "#{actor ? 'member' : 'anonymous'} denied #{name}"
        denied(label, rpc(label, name, params, as: actor), anonymous: actor.nil?)
      end
    end
    %w[admin_bootstrap_whatsapp_approval admin_grant_user_role admin_revoke_user_role].each do |name|
      params = { p_user_id: IDS[1], p_reason: 'Synthetic browser bypass' }
      if name == 'admin_bootstrap_whatsapp_approval'
        params[:p_whatsapp_phone] = '+250788985002'
      else
        params[:p_role_name] = 'platform_owner'
      end
      denied('approved browser denied '+name, rpc(name, name, params))
    end
    code, data = @session.request('private-table', '/whatsapp_approvals?select=*', jwt: token(1))
    check('private approval table absent from public schema', code == 404 && data['code'] == 'PGRST205', code)
    code, data = @session.request('private-profile', '/whatsapp_approvals?select=*', jwt: token(1), headers: { 'Accept-Profile' => 'collect_admin_access' })
    check('API refuses private schema selection', code == 406 && data['code'] == 'PGRST106', code)
    code, data = rpc('private-identity-helper', 'verified_phone', { p_user: IDS[1] })
    check('private identity helper absent from public RPCs', code == 404 && data['code'] == 'PGRST202', code)
    denied('activation before approval rejected', rpc('premature-activation', 'admin_set_user_access', { p_user_id: IDS[1], p_active: true, p_reason: 'No approval' }))

    approval = { p_user_id: IDS[1], p_whatsapp_phone: '+250788985002', p_reason: 'Synthetic reviewed WhatsApp' }
    2.times do |n|
      code, data = rpc("approval-#{n}", 'admin_approve_whatsapp', approval)
      check("exact approval receipt #{n}", code == 200 && data == { 'ok' => true, 'status' => 'approved', 'user_id' => IDS[1] }, code)
    end
    code, data = rpc('approved-list', 'admin_list_admin_users', { p_search: @public_ids.fetch(IDS[1]), p_status: 'approved', p_limit: 25, p_offset: 0, p_sort: 'created_at_desc' })
    check('approved account awaits activation', code == 200 && data['total'] == 1 && data['rows'].first['status'] == 'approved', code)
    2.times do |n|
      code, data = rpc("activation-#{n}", 'admin_set_user_access', { p_user_id: IDS[1], p_active: true, p_reason: 'Synthetic activation' })
      check("exact activation receipt #{n}", code == 200 && data == { 'ok' => true, 'status' => 'active' }, code)
    end
    old_jwt = token(2)
    code, data = rpc('old-session-after-grant', 'admin_current_user', jwt: old_jwt)
    check('preapproval session stays denied after activation', code == 200 && data == {}, code)
    @session.sql("insert into auth.sessions(id,user_id,created_at) values('#{session_id(102)}','#{IDS[1]}',clock_timestamp());", label: 'new-session')
    new_jwt = token(2, session_id: session_id(102))
    code, data = rpc('new-session-after-grant', 'admin_current_user', jwt: new_jwt)
    check('separate new session reaches approved Admin', code == 200 && data['user_id'] == IDS[1], code)
    code, data = rpc('old-session-still-denied', 'admin_current_user', jwt: old_jwt)
    check('new sign-in does not revive old session', code == 200 && data == {}, code)
    code, data = rpc('revoke', 'admin_revoke_whatsapp_approval', { p_user_id: IDS[1], p_reason: 'Synthetic revocation' })
    check('exact revocation receipt', code == 200 && data == { 'ok' => true, 'status' => 'revoked', 'user_id' => IDS[1] }, code)
    code, data = rpc('revoked-same-new-jwt', 'admin_current_user', jwt: new_jwt)
    check('same unexpired new JWT denied after revocation', code == 200 && data == {}, code)
    denied('revoked JWT denied account detail', rpc('revoked-detail', 'admin_get_admin_user', { p_id: IDS[0] }, jwt: new_jwt))
    denied('revoked JWT denied approval mutation', rpc('revoked-approval', 'admin_approve_whatsapp', { p_user_id: IDS[2], p_whatsapp_phone: '+250788985003', p_reason: 'Synthetic bypass' }, jwt: new_jwt))
    code, data = rpc('revoked-detail-readback', 'admin_get_admin_user', { p_id: IDS[1] })
    check('revoked detail has no active roles', code == 200 && data['admin_access'] == false && data['active_roles'] == [], code)
  end

  def rosters!
    { 'list_current_member_group_roster' => 'p_collection_id', 'list_collection_collect_ids' => 'collection' }.each do |name, key|
      GROUPS.first(2).each_with_index do |group, index|
        { 4 => 'owner', 5 => 'active member' }.each do |actor, role|
          code, data = rpc("roster-#{index}-#{name}-#{role}", name, { key => group }, as: actor)
          check("#{index} #{name} allows #{role}", code == 200 && data.is_a?(Array) &&
            data.any? { |row| row['public_id'] == @public_ids.fetch(IDS[3]) } &&
            data.any? { |row| row['public_id'] == @public_ids.fetch(IDS[4]) }, code)
          if name == 'list_current_member_group_roster'
            check("#{index} #{role} roster omits phone and account identifiers", data.all? { |row|
              (row.keys & %w[user_id account_user_id phone phone_e164 whatsapp_phone momo_number revolut_account]).empty? })
          end
        end
        { 1 => 'unrelated platform operator', 3 => 'outsider', 6 => 'left member', 7 => 'other group owner', 8 => 'invited member' }.each do |actor, role|
          label = "#{index} #{name} denies #{role}"
          denied(label, rpc(label, name, { key => group }, as: actor))
        end
        label = "#{index} #{name} denies anonymous"
        denied(label, rpc(label, name, { key => group }, as: nil), anonymous: true)
      end
    end
  end

  def persisted!
    out = @session.sql(<<~SQL, label: 'persisted-effects')
      select json_build_object(
        'approval_audits',(select count(*) from public.audit_logs where entity_id='#{IDS[1]}' and action='admin.whatsapp.approved'),
        'active_roles',(select count(*) from public.admin_user_roles where user_id='#{IDS[1]}' and revoked_at is null),
        'unexpected_outsider_roles',(select count(*) from public.admin_user_roles where user_id='#{IDS[2]}'),
        'distinct_candidate_sessions',(select count(distinct id) from auth.sessions where user_id='#{IDS[1]}'),
        'otp_reservations',(select count(*) from public.otp_rate_limits where phone_hash=repeat('f',64)),
        'payments',(select count(*) from public.payments),
        'ledger',(select count(*) from public.ledger_entries),
        'raw_sms',(select count(*) from public.raw_payment_sms),
        'outbox',(select count(*) from collect_hybrid.sms_notification_outbox));
    SQL
    state = JSON.parse(out.lines.last)
    @session.report[:persisted_effects] = state
    check('approval retry audited once', state['approval_audits'] == 1)
    check('revocation persisted and denied mutations created no role', state['active_roles'] == 0 && state['unexpected_outsider_roles'] == 0)
    check('candidate retained two distinct session records', state['distinct_candidate_sessions'] == 2)
    check('exactly five service OTP reservations persisted', state['otp_reservations'] == 5)
    check('HTTP permission review created no financial or outbound data', state.values_at('payments', 'ledger', 'raw_sms', 'outbox') == [0, 0, 0, 0])
  end

  def otp_limiter!
    params = { p_phone_hash: 'f' * 64, p_ip_hash: nil }
    [nil, 3, 1].each do |actor|
      label = "OTP reservation denies #{actor.nil? ? 'anonymous' : actor == 1 ? 'browser Admin' : 'ordinary member'}"
      denied(label, rpc(label, 'reserve_otp_request', params, as: actor), anonymous: actor.nil?)
    end
    service = @session.token({ role: 'service_role', exp: Time.now.to_i + 600 })
    6.times do |index|
      code, data = rpc("OTP service reservation #{index+1}", 'reserve_otp_request', params, jwt: service)
      check("OTP service reservation #{index+1} has exact boolean outcome", code == 200 && data == (index < 5), code)
    end
    code, data = rpc('OTP malformed hash', 'reserve_otp_request', { p_phone_hash: 'not-a-hash' }, jwt: service)
    check('OTP service invalid hash rejected', code == 400 && data['code'] == '22023', code)
    result = @session.request('OTP direct table', '/otp_rate_limits?select=id', jwt: service)
    denied('OTP service direct table access remains denied', result)
  end

  def run
    begin
      @session.start!
      seed!
      admin!
      rosters!
      otp_limiter!
      persisted!
      @session.report[:runner_source_unchanged] = hashes == @session.report[:runner_sources]
      check('runner source unchanged during execution', @session.report[:runner_source_unchanged])
      @session.report[:status] = 'pass'
    rescue StandardError => error
      @session.report[:status], @session.report[:error] = 'fail', @session.redact(error.message)
    ensure
      @session.finish!
    end
    puts JSON.generate(status: @session.report[:status], checks: @session.report[:checks].length,
      passed: @session.report[:checks].count { |entry| entry[:status] == 'pass' },
      error: @session.report[:error], cleanup_errors: @session.report[:cleanup_errors],
      report: File.join(@session.directory, 'report.json'))
    @session.report[:status] == 'pass'
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: fullstack_api_uat.rb NEW_EVIDENCE_DIRECTORY' unless ARGV.length == 1
  exit(FullstackApiUat.new(ARGV.first).run ? 0 : 1)
end
