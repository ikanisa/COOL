require "json"
require "digest"
require "rbconfig"
ROOT = File.expand_path(__dir__)
Dir.chdir(ROOT)
raise "Unexpected runtime" unless RUBY_VERSION.start_with?("3.3.")
raise "Bootstrap archive changed" unless Digest::SHA256.file("bundler-2.7.2.gem").hexdigest == "1decaf9e2e1acb91b6586a2925c8f3f6da2334a82731a62ff2ded1b83c283871"
bootstrap = File.join(ROOT, "bootstrap-gems")
raise "Bundler installation failed" unless system(RbConfig.ruby, "-S", "gem", "install", "--local", "--no-document", "--install-dir", bootstrap, "bundler-2.7.2.gem")
env = {"GEM_HOME" => bootstrap, "GEM_PATH" => ([bootstrap] + Gem.path).uniq.join(File::PATH_SEPARATOR), "BUNDLE_PATH" => File.join(ROOT, "bundle"), "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "BUNDLE_DISABLE_SHARED_GEMS" => "true", "BUNDLE_USER_HOME" => File.join(ROOT, "bundle-user"), "BUNDLE_APP_CONFIG" => File.join(ROOT, "bundle-config"), "FASTLANE_SKIP_UPDATE_CHECK" => "1", "FASTLANE_OPT_OUT_USAGE" => "1", "FASTLANE_HIDE_CHANGELOG" => "1", "CI" => "1"}
bundle = File.join(bootstrap, "bin", "bundle")
raise "Reviewed bundle resolution failed" unless system(env, RbConfig.ruby, bundle, "lock", "--update", "fastlane", "rubyzip", "--add-checksums")
raise "Frozen bundle installation failed" unless system(env.merge("BUNDLE_FROZEN" => "true"), RbConfig.ruby, bundle, "install", "--jobs", "4", "--retry", "2")
File.write("resolver-completion.json", JSON.pretty_generate({"status" => "pass", "ruby_version" => RUBY_VERSION, "lock_sha256" => Digest::SHA256.file("Gemfile.lock").hexdigest, "bootstrap_bundler" => "2.7.2", "source_versions" => {"fastlane" => "2.240.1", "rubyzip" => "3.4.0"}, "network_scope" => "Public RubyGems dependency resolution/download only; no repository/private configuration mounted", "provider_or_signing_effects" => false}) + "\n")
