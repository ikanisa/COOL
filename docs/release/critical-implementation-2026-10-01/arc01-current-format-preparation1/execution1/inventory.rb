require 'json'
require 'digest'
root = Dir.pwd
upstream = JSON.parse(File.read('third_party/gotrue/UPSTREAM-SHA256.json'))
raw = IO.popen(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart'], &:read)
files = raw.split("\0").uniq.sort.select { |p| File.file?(p) }
files.reject! { |p| p.start_with?('docs/release/') }
files.reject! do |p|
  p.start_with?('third_party/gotrue/') && upstream[p.delete_prefix('third_party/gotrue/')] == Digest::SHA256.file(p).hexdigest
end
puts JSON.generate({count: files.length, paths: files})
