#!/usr/bin/env ruby
# Fixture-only native smoke, frame-sampling and host-driven lifecycle checks.
require 'json'
require 'open3'
require 'pty'
require 'fileutils'
require 'time'
require 'digest'

device = ENV.fetch('IOS_UAT_SIMULATOR_ID', '')
abort('Exact disposable-simulator confirmation is required.') if device.empty? ||
  ENV['IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR'] != device
flutter = ENV.fetch('FLUTTER')
output = File.expand_path(ENV.fetch('IOS_UAT_EVIDENCE_DIR'))
root = File.expand_path('..', __dir__)
xcrun = '/usr/bin/xcrun'
inventory, error, status = Open3.capture3(xcrun, 'simctl', 'list', 'devices', '--json')
abort(error) unless status.success?
simulator = JSON.parse(inventory).fetch('devices').values.flatten.find { |item| item['udid'] == device }
abort('Approved simulator must already be booted.') unless simulator && simulator['state'] == 'Booted'
FileUtils.mkdir_p(output)
log_path = File.join(output, 'native_followup.log')
abort('Refusing to overwrite previous native evidence.') if File.exist?(log_path)
target = 'integration_test/mobile_native_followup_device_uat_test.dart'
command = ['bash', 'scripts/ios_uat_build_and_drive.sh', flutter,
  'test_driver/integration_test.dart', target, device, 'app.cool.mobile',
  File.join(root, 'build/ios/iphonesimulator/Collect.app'),
  '--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true']
started = Time.now
actions = []
text = +''
host_action_done = false
timed_out = false
exit_status = nil
Dir.chdir(root) do
  reader, writer, pid = PTY.spawn(ENV.to_h.merge(
    'INTEGRATION_SCREENSHOT_DIR' => File.join(output, 'screenshots')
  ), *command)
  writer.close
  File.open(log_path, 'wb') do |log|
    loop do
      if IO.select([reader], nil, nil, 0.5)
        begin
          chunk = reader.readpartial(16_384)
          log.write(chunk)
          log.flush
          text << chunk
        rescue EOFError, Errno::EIO
          break
        end
      end
      if !host_action_done && text.include?('collect_ios_lifecycle_uat:ready-for-background')
        host_action_done = true
        ['com.apple.Preferences', 'app.cool.mobile'].each_with_index do |bundle, index|
          sleep 2 if index == 1
          _, launch_error, launch_status = Open3.capture3(xcrun, 'simctl', 'launch', device, bundle)
          actions << {at: Time.now.utc.iso8601, action: 'launch', bundle: bundle,
            success: launch_status.success?, error: launch_error.strip}
        end
      end
      if Time.now - started > 900
        timed_out = true
        begin
          Process.kill('TERM', -pid)
        rescue Errno::ESRCH
          # The child already exited.
        end
        sleep 2
        begin
          Process.kill('KILL', -pid)
        rescue Errno::ESRCH
          # The child already exited.
        end
        break
      end
    end
  end
  reader.close unless reader.closed?
  _, exit_status = Process.waitpid2(pid)
end
required = ['[ios-uat-build] fresh-build-ready bundle=app.cool.mobile',
  'All tests passed', 'collect_perf_complete:',
  'collect_ios_lifecycle_uat:contribution-review-preserved',
  'collect_ios_lifecycle_uat:pass']
missing = required.reject { |marker| text.include?(marker) }
passed = exit_status.success? && !timed_out && missing.empty? &&
  actions.length == 2 && actions.all? { |action| action[:success] } &&
  !text.match?(/Some tests failed|Test failed\.|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK/)
File.write(File.join(output, 'summary.json'), JSON.pretty_generate({
  generated_at: Time.now.utc.iso8601, status: passed ? 'pass' : 'fail',
  simulator: simulator.slice('name', 'udid', 'state'), fixture_only: true,
  target: target, target_sha256: Digest::SHA256.file(File.join(root, target)).hexdigest,
  exit_code: exit_status.exitstatus, timed_out: timed_out, missing_markers: missing,
  host_actions: actions, log_sha256: Digest::SHA256.file(log_path).hexdigest,
  physical_device: false, production_or_provider_uat: false,
  performance_scope: 'Debug simulator engine frame samples, not physical/profile-mode acceptance'
}) + "\n")
puts "Native follow-up #{passed ? 'PASS' : 'FAIL'}: #{output}"
exit(passed ? 0 : 1)
