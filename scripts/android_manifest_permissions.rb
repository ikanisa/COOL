require 'rexml/document'
require 'rexml/xpath'

# Receiver android:permission restricts who may send broadcasts; it does not
# request a permission for this app. Inspect permission elements, not strings.
module AndroidManifestPermissions
  ANDROID_NS = 'http://schemas.android.com/apk/res/android'.freeze
  TOOLS_NS = 'http://schemas.android.com/tools'.freeze

  def self.requested(xml)
    document = REXML::Document.new(xml)
    raise ArgumentError, 'Expected an Android manifest' unless document.root&.name == 'manifest'

    document.root.elements.map do |element|
      next unless %w[uses-permission uses-permission-sdk-23 uses-permission-sdk-m].include?(element.name)
      next if attribute(element, TOOLS_NS, 'node') == 'remove'

      name = attribute(element, ANDROID_NS, 'name')
      raise ArgumentError, 'Permission name is missing' if name.to_s.empty?
      name
    end.compact.uniq.sort
  end

  def self.sms_receiver_protected?(xml)
    receivers = REXML::XPath.match(REXML::Document.new(xml), '/manifest/application/receiver').select do |receiver|
      attribute(receiver, ANDROID_NS, 'name').to_s.end_with?('.CollectSmsReceiver')
    end
    !receivers.empty? && receivers.all? do |receiver|
      attribute(receiver, ANDROID_NS, 'permission') == 'android.permission.BROADCAST_SMS'
    end
  end

  def self.attribute(element, namespace, name)
    element.attributes.each_attribute.find { |item| item.name == name && item.namespace == namespace }&.value
  end
end
