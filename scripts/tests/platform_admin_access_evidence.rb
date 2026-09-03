require 'json'
require 'digest'
require 'time'
ROOT=File.expand_path('../..',__dir__)
PACKET='/Volumes/PRO-G40/Agents/Codex/2026-05-15/Codex Professional Agents/desktop-output/flutter/engagements/collect/go-live-2026-09-02'.freeze
sources=%w[
  supabase/migrations/20260902140151_platform_admin_whatsapp_approval.sql
  lib/admin/core/admin_runtime.dart lib/admin/core/admin_detail_runtime.dart
  lib/admin/core/admin_platform_access.dart lib/admin/core/admin_list_specs.dart
  lib/admin/core/admin_evidence_mode.dart test/admin_platform_access_test.dart test/admin_pwa_test.dart
  scripts/tests/platform_admin_access_uat.rb scripts/tests/platform_admin_access_contract.sql
  scripts/tests/platform_admin_access_concurrency.rb scripts/tests/platform_admin_access_http.rb
  scripts/tests/platform_admin_access_recovery.rb scripts/tests/platform_admin_access_evidence.rb
  scripts/audits/platform_admin_access_advisors.rb
  docs/release/ADMIN_WHATSAPP_PREAPPROVAL_2026-09-02.md
  docs/release/CONTROLLED_ROLLOUT_2026-09-02.md docs/RECOVERY_RUNBOOK.md
].map{|file|ROOT+'/'+file}
evidence=Dir.glob(PACKET+'/logs/platform-admin*')+Dir.glob(PACKET+'/screenshots/platform-admin/*.png')+
  Dir.glob(PACKET+'/backend/{58,59,60,61,62,63}-platform-admin*.json')+
  %w[PLAN.md RESULTS.md GO_LIVE_GATES.md engagement_manifest.json].map{|file|PACKET+'/'+file}
fingerprint=lambda do |paths|
  paths.sort.map do |path|
    raise "Missing evidence #{path}" unless File.file?(path)
    {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest}
  end
end
checks={
  full_flutter:File.read(PACKET+'/logs/platform-admin-full-regression-fixed.log').include?('+552: All tests passed!'),
  analyzer:File.read(PACKET+'/logs/platform-admin-analyze-final.log').include?('No issues found!'),
  sql_contract:File.read(PACKET+'/logs/platform-admin-final-contract.log').include?('PLATFORM_ADMIN_ACCESS_CONTRACT_PASS'),
  member_separation:File.read(PACKET+'/logs/platform-admin-member-regressions-complete.log').include?('PLATFORM_AND_MEMBER_REGRESSIONS_PASS'),
  http:JSON.parse(File.read(PACKET+'/backend/59-platform-admin-http.json'))['checks'].all?{|row|row['status']=='pass'},
  concurrency:JSON.parse(File.read(PACKET+'/backend/58-platform-admin-concurrency.json'))['checks'].all?{|row|row['status']=='pass'},
  access_recovery:JSON.parse(File.read(PACKET+'/backend/62-platform-admin-recovery-api-v2.json'))['status']=='pass',
  secret_hygiene:File.read(PACKET+'/logs/platform-admin-secret-hygiene.log').include?('fallback secret scan passed')
}
raise 'Evidence gate failed' unless checks.values.all?
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,scope:'platform-only WhatsApp approval; uncommitted local candidate',
  checks:checks,sources:fingerprint.call(sources),evidence:fingerprint.call(evidence),
  production_go:false,production_changes:false,live_refresh:'connector_permission_denied',
  limitations:['Local/synthetic evidence, not deployed or physical/provider UAT','Recovery covers access state in the same cluster; not production RPO/RTO',
    'Earlier failed/prior-revision evidence retained; final API recovery is 62','Original signed-in preview, installed app and member database unchanged'])
