# frozen_string_literal: true

# Exercise the maintained renderer at its existing test boundary. This does not
# run, override or accept the whole-site stale-media gate.
require 'digest'
require 'json'
require 'fileutils'

root = File.expand_path('../../../..', __dir__)
packet = __dir__
destination = File.join(root, '.cache/public-share-ui-current-20261002-batch1-fixture')
raise 'Fresh fixture destination required' if File.exist?(destination)
builder = File.join(root, 'scripts/public_static_site_build.rb')
source = File.read(builder)
boundary = source.index("\nallowed_build_roots = [") or raise 'Maintained renderer execution boundary absent'
inputs = %w[
  scripts/public_static_site_build.rb scripts/public_app_media.rb scripts/public_photography.rb
  scripts/product_capabilities.rb scripts/assets/build_public_photography.mjs
  scripts/qa/asset_manifest_integrity.rb
  content/product/collect_capabilities.json
  web/public/layout.css web/public/revolut.css web/public/photography/manifest.json
  assets/brand/collect_runtime/app_icons/app-icon-rule.png
  assets/typefaces/Inter-Variable.ttf assets/typefaces/AeonikPro-Regular.ttf
  assets/typefaces/AeonikPro-Medium.ttf assets/typefaces/OFL-Inter.txt
  .cache/public-static-current-20261002-batch2-attempt1/manifest.json
]
inputs += Dir.glob(File.join(root, 'content/legal/*.yaml')).map { |file| file.delete_prefix(root + '/') }
inputs += Dir.glob(File.join(root, 'assets/marketing/rwanda/*.png')).map { |file| file.delete_prefix(root + '/') }
inputs += Dir.glob(File.join(root, 'web/public/photography/*')).select { |file| File.file?(file) }.map { |file| file.delete_prefix(root + '/') }
inputs << File.expand_path(__FILE__).delete_prefix(root + '/')
snapshot = -> { inputs.uniq.sort.to_h { |name| [name, Digest::SHA256.file(File.join(root, name)).hexdigest] } }
before = snapshot.call
renderer_module = Module.new
renderer_module.module_eval(source[0...boundary], builder, 1)
renderer = Object.new.extend(renderer_module)
photography = PublicPhotography.new(root)
photography.photos
FileUtils.mkdir_p(destination)
write = lambda do |relative, content|
  path = File.join(destination, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, content)
end
write.call('app/index.html', renderer.share_landing_page_html(kind: :app))
write.call('c/index.html', renderer.share_landing_page_html(kind: :group))
write.call('group-link/index.html', renderer.share_landing_page_html(kind: :group))
core, sections = renderer.split_stylesheets(renderer.stylesheet)
write.call('styles.css', core)
write.call('sections.css', sections)
write.call('revolut.css', photography.prepare_css(File.read(File.join(root, 'web/public/revolut.css'))))
write.call('site.js', renderer.site_js)
write.call('manifest.json', File.binread(File.join(root, '.cache/public-static-current-20261002-batch2-attempt1/manifest.json')))
write.call('icons/collect.png', File.binread(File.join(root, 'assets/brand/collect_runtime/app_icons/app-icon-rule.png')))
%w[Inter-Variable.ttf AeonikPro-Regular.ttf AeonikPro-Medium.ttf OFL-Inter.txt].each do |name|
  write.call('assets/typefaces/' + name, File.binread(File.join(root, 'assets/typefaces', name)))
end
after = snapshot.call
files = Dir.glob(File.join(destination, '**/*'), File::FNM_DOTMATCH).select { |file| File.file?(file) }.sort.to_h do |file|
  [file.delete_prefix(destination + '/'), Digest::SHA256.file(file).hexdigest]
end
receipt = {
  status: before == after ? 'pass' : 'fail',
  kind: 'isolated_actual_maintained_share_renderer_fixture',
  source_before: before, source_after: after, listed_inputs_unchanged: before == after,
  full_source_prefix_sha256: Digest::SHA256.hexdigest(source[0...boundary]),
  existing_renderer_test_boundary: 'PublicLegalRenderingTest: SOURCE.index("\\nallowed_build_roots = [")',
  fixture: destination, files: files,
  full_current_static_media_gate_passed: false,
  scope: 'Exact maintained app/group share renderer, stylesheet transforms and site.js on a private local fixture. This bypasses no production gate and grants no full current-source static/media/native/legal/hosted/release acceptance.'
}
File.write(File.join(packet, 'share-fixture-build.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.generate(status: receipt[:status], fixture_files: files.length, source_inputs: before.length)
raise 'Fixture source changed while rendering' unless receipt[:status] == 'pass'
