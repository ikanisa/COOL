require 'json'
require 'digest'
require 'open3'
root = '/work/checkout'
Dir.chdir(root)
expected = JSON.parse(File.read('/opt/arc01/source-inventory.json'))
raw, error, status = Open3.capture3('git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart')
abort error unless status.success?
paths = raw.split("\0").uniq.sort.select { |path| File.file?(path) }
paths.reject! { |path| path.start_with?('docs/release/') }
upstream = JSON.parse(File.read('third_party/gotrue/UPSTREAM-SHA256.json'))
paths.reject! do |path|
  path.start_with?('third_party/gotrue/') && upstream[path.delete_prefix('third_party/gotrue/')] == Digest::SHA256.file(path).hexdigest
end
fixture = 'lib/arc01_deliberately_unformatted_fixture.dart'
expected_paths = expected['applicable_formatter_paths']
expected_paths = (expected_paths + [fixture]).sort if File.file?(fixture)
abort 'Maintained inventory parity mismatch' unless paths == expected_paths
hashes = expected['copied_input_sha256'].keys.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
abort 'Private source bytes changed' unless hashes == expected['copied_input_sha256']
puts JSON.generate({inventory_exact: true, applicable_count: paths.size, paths: paths, source_sha256: hashes, fixture_present: File.file?(fixture), alternate_object_store: File.exist?('.git/objects/info/alternates'), root_package_config: File.exist?('.dart_tool/package_config.json')})
