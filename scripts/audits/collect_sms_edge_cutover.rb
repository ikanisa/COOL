# Deploy only the two reviewed receipt handlers. No function deletion, secret
# rotation, OTP dispatch, SQL mutation or payment ingestion is performed here.
require_relative 'collect_production_cutover'
require 'open3'
require 'tmpdir'

module CollectSmsEdgeCutover
  SLUGS = %w[ingest-payment-sms parse-payment-sms].freeze
  CLI = '/Users/jeanbosco/.npm/_npx/1517203cdeef2779/node_modules/@supabase/cli-darwin-arm64/bin/supabase'.freeze
  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    STDOUT.sync = true
    puts 'Awaiting release credentials on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    input = JSON.parse(raw.to_s)
    raw.clear
    raise 'Wrong project scope' unless input.fetch('project_url') == "https://#{CollectProductionCutover::REF}.supabase.co"
    token = input.fetch('access_token')
    raise 'Cutover migration history is incomplete' unless CollectProductionCutover.history(token).length==111
    before = CollectProductionCutover.request(token,'/functions').select { |f|SLUGS.include?(f['slug']) }
    raise 'Expected both existing functions' unless before.length==2
    report = {started_at:Time.now.utc.iso8601,project:CollectProductionCutover::REF,
      before:before.map { |f|f.slice('slug','version','verify_jwt','ezbr_sha256') },
      deployments:[],provider_sends:0,functions_deleted:0,secrets_changed:0}
    env = {'SUPABASE_ACCESS_TOKEN'=>token}
    begin
      SLUGS.each do |slug|
        out,err,status = Open3.capture3(env,CLI,'functions','deploy',slug,'--project-ref',CollectProductionCutover::REF,'--use-api',
          chdir:CollectProductionCutover::ROOT)
        raise "Deployment failed for #{slug}; CLI exit #{status.exitstatus}" unless status.success?
        puts "Deployed #{slug}; verifying downloaded source."
        Dir.mktmpdir('collect-edge-readback-') do |dir|
          _out,_err,download = Open3.capture3(env,CLI,'functions','download',slug,'--project-ref',CollectProductionCutover::REF,
            '--use-api','--workdir',dir)
          raise "Deployed source download failed for #{slug}" unless download.success?
          files = Dir[File.join(dir,'supabase/functions/**/*.ts')].sort
          raise 'No downloaded TypeScript sources' if files.empty?
          checked = files.map do |file|
            relative = file.delete_prefix(dir+'/')
            local = File.join(CollectProductionCutover::ROOT,relative)
            sha = Digest::SHA256.file(file).hexdigest
            raise "Deployed source mismatch: #{relative}" unless File.file?(local) && Digest::SHA256.file(local).hexdigest==sha
            {file:relative,sha256:sha}
          end
          report[:deployments] << {slug:slug,source_readback:'exact_match',files:checked}
        end
      end
      after = CollectProductionCutover.request(token,'/functions').select { |f|SLUGS.include?(f['slug']) }
      raise 'Function runtime not active or JWT guard changed' unless after.all? { |f|f['status']=='ACTIVE' && f['verify_jwt']==(f['slug']=='ingest-payment-sms') }
      report[:after] = after.map { |f|f.slice('slug','version','status','verify_jwt','ezbr_sha256') }
      report[:result] = 'TWO_RECEIPT_FUNCTIONS_DEPLOYED_SOURCE_VERIFIED'
    rescue StandardError => error
      report[:result] = 'STOPPED_REQUIRES_READBACK'
      report[:error] = error.message.gsub(token,'[redacted]')
    ensure
      report[:finished_at] = Time.now.utc.iso8601
      File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(report)+"\n") }
      puts JSON.generate(report:output,result:report[:result])
    end
    report[:result]=='TWO_RECEIPT_FUNCTIONS_DEPLOYED_SOURCE_VERIFIED'
  ensure
    raw&.clear
    token&.clear
    input&.clear
  end
end

if $PROGRAM_NAME==__FILE__
  abort('Usage: collect_sms_edge_cutover.rb NEW_REPORT.json') unless ARGV.length==1
  exit(CollectSmsEdgeCutover.run(ARGV.first) ? 0 : 1)
end
