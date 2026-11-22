# Real macOS encrypted-volume rehearsal, synthetic bytes only. No network calls.
# Pass the stable compiled helper and a NEW JSON report path.
require 'json'
require 'open3'
require 'securerandom'
require 'digest'
require 'time'

executable, output = ARGV
raise 'Executable and new JSON report required' unless executable && File.executable?(executable) &&
  output && output.end_with?('.json') && !File.exist?(output)
identifier = "collect-fixture-#{Time.now.utc.strftime('%Y%m%dT%H%M%S').downcase}-#{SecureRandom.hex(4)}"
checks = []
call = lambda do |action, id = identifier, expected_success = true|
  stdout, stderr, status = Open3.capture3(executable, action, id)
  raise "Unexpected #{action} result (#{status.exitstatus}); details withheld" unless status.success? == expected_success
  expected_success ? JSON.parse(stdout) : stderr
end
check = lambda do |label, condition|
  raise "FAIL #{label}" unless condition
  checks << label
  puts "PASS #{label}"
end
vault = nil
mounted = false
begin
  call.call('create', '../outside-target', false)
  check.call('path_traversal_refused', true)
  call.call('remove', identifier, false)
  check.call('unsupported_operation_refused', true)
  vault = call.call('create')
  check.call('encrypted_image_created', vault.dig('encryption', 'encrypted') == true && vault['attached'] == false)
  check.call('no_secret_output', vault['secret_values_output'] == false && !JSON.generate(vault).match?(/[0-9a-f]{64}/))
  call.call('create', identifier, false)
  check.call('overwrite_refused', true)
  check.call('private_image_permissions', File.stat(vault.fetch('image')).mode & 0o777 == 0o700)
  mount = call.call('attach')
  mounted = true
  check.call('keychain_retrieval_and_mount', mount['attached'] == true)
  call.call('attach', identifier, false)
  check.call('duplicate_attach_refused', true)
  data = ("SYNTHETIC COLLECT ENCRYPTION REHEARSAL — NO CUSTOMER DATA\n" * 16_384)
  file = File.join(mount.fetch('mount'), 'synthetic-only.txt')
  File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |handle| handle.write(data); handle.fsync }
  digest = Digest::SHA256.hexdigest(data)
  check.call('fixture_hash_before_detach', Digest::SHA256.file(file).hexdigest == digest)
  check.call('fixture_permissions', File.stat(file).mode & 0o777 == 0o600)
  call.call('detach')
  mounted = false
  check.call('plaintext_unavailable_when_detached', !File.exist?(file))
  _out, _err, status = Open3.capture3('/usr/bin/hdiutil', 'attach', vault.fetch('image'),
    '-stdinpass', '-nomount', '-nobrowse', stdin_data: "deliberately-wrong-fixture-password\0")
  check.call('wrong_password_rejected', !status.success?)
  check.call('wrong_password_left_image_detached', call.call('inspect')['attached'] == false)
  call.call('readonly')
  mounted = true
  check.call('fixture_hash_after_keychain_remount', Digest::SHA256.file(file).hexdigest == digest)
  rejected = false
  begin
    File.open(File.join(mount.fetch('mount'), 'must-not-write'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |handle| handle.write('fixture') }
  rescue Errno::EROFS, Errno::EACCES
    rejected = true
  end
  check.call('readonly_remount_rejects_writes', rejected)
  call.call('detach')
  mounted = false
  check.call('final_image_detached', call.call('inspect')['attached'] == false)
  report = { captured_at: Time.now.utc.iso8601, mode: 'synthetic_only_no_network_no_database_export',
    result: 'PASS', checks: checks, fixture_bytes: data.bytesize, fixture_sha256: digest,
    vault: vault, helper_sha256: Digest::SHA256.file(executable).hexdigest,
    limitations: ['No production data copied', 'No database restore performed',
      'Key remains in this Mac Keychain; off-device key escrow not established',
      'Encrypted disk image is not an off-site backup'] }
  File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |handle| handle.write(JSON.pretty_generate(report) + "\n") }
ensure
  call.call('detach') if mounted
end
