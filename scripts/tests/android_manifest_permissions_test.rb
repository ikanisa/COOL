require 'minitest/autorun'
require_relative '../android_manifest_permissions'

class AndroidManifestPermissionsTest < Minitest::Test
  def manifest(body)
    %(<manifest xmlns:a="http://schemas.android.com/apk/res/android" xmlns:t="http://schemas.android.com/tools">#{body}</manifest>)
  end

  def test_receiver_guard_is_not_an_app_permission
    xml = manifest('<uses-permission a:name="android.permission.RECEIVE_SMS"/><application><receiver a:name=".receiver_sms.CollectSmsReceiver" a:permission="android.permission.BROADCAST_SMS"/></application>')
    assert_equal ['android.permission.RECEIVE_SMS'], AndroidManifestPermissions.requested(xml)
    assert AndroidManifestPermissions.sms_receiver_protected?(xml)
  end

  def test_actual_restricted_requests_remain_detectable
    xml = manifest('<uses-permission a:name="android.permission.BROADCAST_SMS"/><uses-permission-sdk-23 a:name="android.permission.READ_SMS"/>')
    assert_equal %w[android.permission.BROADCAST_SMS android.permission.READ_SMS], AndroidManifestPermissions.requested(xml)
  end

  def test_comments_and_removed_permissions_are_not_requests
    xml = manifest('<!-- <uses-permission a:name="android.permission.READ_SMS"/> --><uses-permission a:name="android.permission.SEND_SMS" t:node="remove"/>')
    assert_empty AndroidManifestPermissions.requested(xml)
  end

  def test_missing_or_unprotected_receiver_fails
    refute AndroidManifestPermissions.sms_receiver_protected?(manifest('<application/>'))
    refute AndroidManifestPermissions.sms_receiver_protected?(manifest('<application><receiver a:name=".receiver_sms.CollectSmsReceiver"/></application>'))
  end

  def test_malformed_manifest_fails_closed
    assert_raises(REXML::ParseException) { AndroidManifestPermissions.requested('<manifest><') }
    assert_raises(ArgumentError) { AndroidManifestPermissions.requested('<unexpected/>') }
  end
end
