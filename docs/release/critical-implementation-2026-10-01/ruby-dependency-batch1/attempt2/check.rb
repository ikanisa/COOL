require "json"
require "digest"
require "open3"
require "rbconfig"
ROOT = File.expand_path(__dir__)
bootstrap = File.join(ROOT, "bootstrap-gems")
env = {"GEM_HOME" => bootstrap, "GEM_PATH" => ([bootstrap] + Gem.path).uniq.join(File::PATH_SEPARATOR), "BUNDLE_PATH" => File.join(ROOT, "bundle"), "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "BUNDLE_DISABLE_SHARED_GEMS" => "true", "BUNDLE_FROZEN" => "true", "BUNDLE_USER_HOME" => File.join(ROOT, "bundle-user"), "BUNDLE_APP_CONFIG" => File.join(ROOT, "bundle-config"), "FASTLANE_SKIP_UPDATE_CHECK" => "1", "FASTLANE_OPT_OUT_USAGE" => "1", "FASTLANE_HIDE_CHANGELOG" => "1", "CI" => "1", "PATH" => File.join(ROOT, "node-v24.19.0-linux-arm64/bin") + File::PATH_SEPARATOR + ENV.fetch("PATH")}
bundle = File.join(bootstrap, "bin", "bundle")
Dir.chdir(File.join(ROOT, "offline-repo"))
checks = [
 ["ruby-version", [RbConfig.ruby, "--version"]],
 ["python-version", ["python3", "--version"]],
 ["frozen-bundle-check", [RbConfig.ruby, bundle, "check"]],
 ["fastlane-version", [RbConfig.ruby, bundle, "exec", "fastlane", "--version"]],
 ["fastlane-lanes", [RbConfig.ruby, bundle, "exec", "fastlane", "lanes"]],
 ["fastlane-action-load", [RbConfig.ruby, bundle, "exec", "ruby", "-e", 'require "fastlane"; Fastlane.load_actions; [Fastlane::Actions::DeliverAction, Fastlane::Actions::PilotAction, Fastlane::Actions::SupplyAction, Fastlane::Actions::UploadAppPrivacyDetailsToAppStoreAction].each { |action| raise "Missing action configuration" unless action.available_options.any? }; puts "DELIVERY_ACTIONS_LOADED"']],
 ["rubyzip-security", [RbConfig.ruby, bundle, "exec", "ruby", "scripts/tests/ruby_dependency_security_test.rb"]],
 ["ios-offline-contract", ["python3", "scripts/tests/ios_delivery_contract_test.py"]]
]
results = []
checks.each do |name, command|
 output, error, status = Open3.capture3(env, *command)
 File.write(File.join(ROOT, name + ".stdout"), output)
 File.write(File.join(ROOT, name + ".stderr"), error)
 results << {"name" => name, "exit_code" => status.exitstatus, "command" => command}
 File.write(File.join(ROOT, "offline-checks-progress.json"), JSON.pretty_generate(results) + "\n")
 puts "#{name}: exit #{status.exitstatus}"
 raise "Failed actual check: #{name}" unless status.success?
end
raise "Baseline archive changed" unless Digest::SHA256.file(File.join(ROOT, "rubyzip-2.4.1.gem")).hexdigest == "8577c88edc1fde8935eb91064c5cb1aef9ad5494b940cf19c775ee833e075615"
baseline = File.join(ROOT, "baseline-gems")
output, error, status = Open3.capture3(env, RbConfig.ruby, "-S", "gem", "install", "--local", "--no-document", "--install-dir", baseline, File.join(ROOT, "rubyzip-2.4.1.gem"))
File.write(File.join(ROOT, "prior-rubyzip-install.stdout"), output)
File.write(File.join(ROOT, "prior-rubyzip-install.stderr"), error)
raise "Failed comparison-only install" unless status.success?
baseline_env = env.merge("GEM_HOME" => baseline, "GEM_PATH" => ([baseline] + Gem.default_path).uniq.join(File::PATH_SEPARATOR), "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_PATH" => nil, "COLLECT_RUBYZIP_EXPECTED_VERSION" => "2.4.1")
output, error, status = Open3.capture3(baseline_env, RbConfig.ruby, "scripts/tests/ruby_dependency_security_test.rb")
File.write(File.join(ROOT, "prior-rubyzip-security.stdout"), output)
File.write(File.join(ROOT, "prior-rubyzip-security.stderr"), error)
negative = JSON.parse(output)
raise "Prior vulnerability not exercised" unless status.exitstatus == 1 && negative.fetch("rubyzip_version") == "2.4.1" && negative.fetch("cases").map { |item| item.fetch("passed") } == [true, false, false]
results << {"name" => "prior-rubyzip-two-sibling-vulnerabilities", "exit_code" => status.exitstatus, "expected_failure" => true, "benign_passed" => true, "hostile_cases_failed" => 2}
File.write(File.join(ROOT, "offline-completion.json"), JSON.pretty_generate({"status" => "pass", "checks" => results, "ruby_version" => RUBY_VERSION, "lock_sha256" => Digest::SHA256.file(File.join(ROOT, "Gemfile.lock")).hexdigest, "network_none_requested" => true, "provider_or_signing_effects" => false}) + "\n")
