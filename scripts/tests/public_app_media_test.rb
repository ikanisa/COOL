require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'base64'
require_relative '../public_app_media'

class PublicAppMediaTest < Minitest::Test
  def fixture
    Dir.mktmpdir('collect-public-media-') do |root|
      FileUtils.mkdir_p([File.join(root, 'web/public/app-screens'), File.join(root, '.cache/captures'), File.join(root, 'lib')])
      File.write(File.join(root, 'pubspec.yaml'), 'version: 1.2.4+23')
      File.write(File.join(root, 'pubspec.lock'), 'fixture')
      File.write(File.join(root, 'lib/app.dart'), 'current application')
      image = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII=')
      asset = File.join(root, 'web/public/app-screens/home.png')
      File.binwrite(asset, image)
      File.binwrite(File.join(root, '.cache/captures/home.png'), image)
      manifest = {
        'runtime_sha256' => PublicAppMedia.new(root).runtime_fingerprint,
        'screens' => [{'id' => 'home', 'file' => 'home.png', 'capture' => '.cache/captures/home.png',
                      'sha256' => Digest::SHA256.hexdigest(image), 'width' => 1, 'height' => 1,
                      'reviewed_for_website' => true, 'capture_kind' => 'native_ios_fixture'}]
      }
      File.write(File.join(root, 'web/public/app-screens/manifest.json'), JSON.generate(manifest))
      File.write(File.join(root, 'web/public/app-screens/capture-provenance.json'), JSON.generate({
        'status' => 'pass', 'installed_matches_retained_bundle' => true,
        'runtime_sha256' => manifest['runtime_sha256'],
        'captures' => [{'path' => '.cache/captures/home.png', 'sha256' => Digest::SHA256.hexdigest(image), 'width' => 1, 'height' => 1}]
      }))
      yield root, asset
    end
  end

  def test_unchanged_original_capture_is_available
    fixture { |root, _| assert_equal '/assets/app-screens/home.png', PublicAppMedia.new(root).screens.fetch('home')['url'] }
  end

  def test_replaced_or_edited_image_is_rejected
    fixture do |root, asset|
      File.binwrite(asset, 'invented replacement image')
      assert_match(/differs from its original/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_app_change_requires_new_captures
    fixture do |root, _|
      File.write(File.join(root, 'lib/app.dart'), 'changed application')
      assert_match(/runtime changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_clean_checkout_uses_retained_native_capture_inventory
    fixture do |root, _|
      FileUtils.rm_r(File.join(root, '.cache'))
      assert_equal '/assets/app-screens/home.png', PublicAppMedia.new(root).screens.fetch('home')['url']
    end
  end

  def test_fabricated_capture_manifest_is_rejected
    fixture do |root, _|
      path = File.join(root, 'web/public/app-screens/capture-provenance.json')
      provenance = JSON.parse(File.read(path))
      provenance['captures'][0]['sha256'] = 'invented'
      File.write(path, JSON.generate(provenance))
      assert_match(/absent from native capture provenance/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end
end
