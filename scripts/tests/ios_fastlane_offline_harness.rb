# Execute actual iOS lanes with real source preflight and fake Apple actions.
require 'json'
require 'open3'
module UI
  def self.user_error!(message)
    raise message
  end
  def self.message(_message); end
end
@lanes = {}
@effects = []
def default_platform(_name); end
def desc(_text); end
def platform(name)
  @platform = name
  yield
end
def lane(name, &block)
  @lanes[[@platform, name]] = block
end
def sh(command)
  if command.include?('ios_delivery_guard.py')
    output, error, result = Open3.capture3(command)
    raise(error + output) unless result.success?
  else
    @effects << ['mock_readiness', command]
  end
end
def app_store_connect_api_key(**_options)
  @effects << ['mock_api_key']
  :synthetic_api_key
end
def deliver(**options)
  raise 'public release forbidden in this scope' unless options[:submit_for_review] == false && options[:automatic_release] == false
  @effects << ['mock_metadata_upload']
end
def pilot(**options)
  raise 'external distribution forbidden' unless options[:distribute_external] == false
  @effects << ['mock_internal_upload']
end
def upload_app_privacy_details_to_app_store(**_options)
  @effects << ['mock_privacy_publish']
end
source, lane_name, output = ARGV
begin
  eval(File.read(source), binding, source)
  @lanes.fetch([:ios, lane_name.to_sym]).call
  File.write(output, JSON.generate(status: 'pass', effects: @effects))
rescue StandardError => error
  File.write(output, JSON.generate(status: 'blocked', effects: @effects, reason: error.message))
  exit 1
end
