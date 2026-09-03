# Only the owner-selected existing Collect ID. No Auth users, sessions, OTPs,
# verification overrides or group roles are created by this procedure.
require_relative 'collect_production_cutover'

module CollectFirstOperatorCutover
  def self.quote(value)
    "'#{value.gsub("'", "''")}'"
  end

  def self.run(mode, output)
    raise 'Expected check, activate or readback' unless %w[check activate readback].include?(mode)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    STDOUT.sync = true
    puts 'Awaiting selected operator and credentials on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    input = JSON.parse(raw.to_s)
    raw.clear
    raise 'Wrong credential project' unless input.fetch('project_url') == "https://#{CollectProductionCutover::REF}.supabase.co"
    phone = input.fetch('selected_phone')
    raise 'Canonical selected phone required' unless phone.match?(/\A\+[1-9]\d{7,14}\z/)
    token = input.fetch('access_token')
    project = CollectProductionCutover.request(token,'')
    raise 'Authenticated project mismatch' unless project['id']==CollectProductionCutover::REF && project['name']=='COOL' && project['status']=='ACTIVE_HEALTHY'
    rows = CollectProductionCutover.request(token,'/database/query',{
      query: <<~SQL, parameters:[phone.delete_prefix('+')],read_only:true})
        SELECT u.id,p.public_id,
          EXISTS(SELECT 1 FROM public.admin_user_roles ur JOIN public.admin_roles r ON r.id=ur.role_id
            WHERE ur.user_id=u.id AND r.name='platform_owner' AND ur.revoked_at IS NULL) AS has_combined_role
        FROM auth.users u JOIN public.profiles p ON p.id=u.id
        WHERE regexp_replace(u.phone,'[^0-9]','','g')=$1 AND u.phone_confirmed_at IS NOT NULL
          AND u.deleted_at IS NULL AND NOT u.is_anonymous AND (u.banned_until IS NULL OR u.banned_until<now());
      SQL
    raise 'Selected identity no longer resolves uniquely' unless rows.length==1 && rows.first['public_id']=='965511'
    selected = rows.first
    uuid = selected.fetch('id')
    raise 'Unexpected account identifier' unless uuid.match?(/\A[0-9a-f-]{36}\z/)
    report = {started_at:Time.now.utc.iso8601,project:CollectProductionCutover::REF,mode:mode,
      selected_collect_id:'965511',verified_existing_identity:true,combined_role_before:selected['has_combined_role'],
      approval_and_role_commit_attempted:false,provider_sends:0,auth_users_created:0,sessions_created:0,group_roles_changed:0}
    begin
      if mode=='activate'
        raise 'Migrations not fully deployed' unless CollectProductionCutover.history(token).length==111
        reason = 'Owner-selected first platform Admin; approved production cutover 2026-09-03'
        sql = <<~SQL
          BEGIN;
          SET LOCAL lock_timeout='5s';
          SET LOCAL statement_timeout='30s';
          SET LOCAL request.jwt.claims='{"role":"service_role"}';
          SET LOCAL ROLE service_role;
          SELECT public.admin_bootstrap_whatsapp_approval(#{quote(uuid)}::uuid,#{quote(phone)},#{quote(reason)});
          SELECT public.admin_bootstrap_platform_owner(#{quote(uuid)}::uuid,#{quote(reason)});
          COMMIT;
        SQL
        report[:approval_and_role_commit_attempted] = true
        CollectProductionCutover.query(token,sql,write:true)
        report[:approval_and_role_commit_confirmed] = true
      end
      if mode!='check'
        state = CollectProductionCutover.catalog_query(token,<<~SQL).first
          SELECT collect_admin_access.approved_identity(#{quote(uuid)}::uuid) AS approved_identity,
            EXISTS(SELECT 1 FROM public.admin_user_roles ur JOIN public.admin_roles r ON r.id=ur.role_id
              WHERE ur.user_id=#{quote(uuid)}::uuid AND r.name='platform_owner' AND ur.revoked_at IS NULL) AS combined_role_active,
            (SELECT count(*) FROM collect_admin_access.whatsapp_approvals WHERE revoked_at IS NULL) AS active_approval_count;
        SQL
        raise 'Activation readback failed' unless state['approved_identity'] && state['combined_role_active'] && state['active_approval_count']==1
        report[:readback] = state
        report[:fresh_whatsapp_sign_in_required] = true
      end
      report[:result] = mode!='check' ? 'SELECTED_OPERATOR_ACTIVATED_FRESH_SIGN_IN_PENDING' : 'SELECTED_OPERATOR_CONFIRMED'
    rescue StandardError => error
      report[:result] = 'FAILED_READBACK_REQUIRED_BEFORE_RETRY'
      report[:error] = error.message.gsub(token,'[redacted]').gsub(phone,'[selected phone]')
    ensure
      report[:finished_at] = Time.now.utc.iso8601
      File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(report)+"\n") }
      puts JSON.generate(report:output,result:report[:result])
    end
    !report[:result].start_with?('FAILED')
  ensure
    raw&.clear
    token&.clear
    phone&.clear
    input&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_first_operator_cutover.rb check|activate|readback NEW_REPORT.json') unless ARGV.length==2
  exit(CollectFirstOperatorCutover.run(*ARGV) ? 0 : 1)
end
