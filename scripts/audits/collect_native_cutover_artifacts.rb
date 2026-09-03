# Inspect generated native artifacts only; never install, upload or submit them.
require 'json'
require 'digest'
require 'open3'
require 'tmpdir'
require 'time'

ROOT = File.expand_path('../..', __dir__)
def capture(*args, env: {})
  out,err,status = Open3.capture3(env,*args)
  raise "Artifact command failed: #{File.basename(args.first)}" unless status.success?
  [out,err]
end

output = ARGV.fetch(0)
raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
paths = {
  apk:'build/app/outputs/flutter-apk/app-production-release.apk',
  aab:'build/app/outputs/bundle/productionRelease/app-production-release.aab',
  ipa:'build/ios/ipa/Collect.ipa'
}
report = {captured_at:Time.now.utc.iso8601,version:'1.2.4+23',installed:false,uploaded:false,store_accepted:false,
  artifacts:paths.transform_values { |p| {path:p,bytes:File.size(File.join(ROOT,p)),sha256:Digest::SHA256.file(File.join(ROOT,p)).hexdigest} }}
badging,_ = capture('/Users/jeanbosco/Library/Android/sdk/build-tools/37.0.0/aapt','dump','badging',paths[:apk])
raise 'Android package/version mismatch' unless badging.include?("package: name='app.cool.mobile' versionCode='23' versionName='1.2.4'")
permissions = badging.scan(/^uses-permission: name='([^']+)'/).flatten
raise 'Unexpected SMS read permission' if permissions.include?('android.permission.READ_SMS')
raise 'Receive-only receipt permission missing' unless permissions.include?('android.permission.RECEIVE_SMS')
java_home='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
signature,_ = capture('/Users/jeanbosco/Library/Android/sdk/build-tools/37.0.0/apksigner','verify','--verbose','--print-certs',paths[:apk],env:{'JAVA_HOME'=>java_home})
expected_cert='9ee12172c78a8a487906d9159bfdd17b4d78aba3541f17b410659e6d60ddcc10'
raise 'APK upload certificate mismatch' unless signature.include?("certificate SHA-256 digest: #{expected_cert}")
bundle_signature,_ = capture(java_home+'/bin/jarsigner','-verify',paths[:aab])
raise 'AAB signature not verified' unless bundle_signature.include?('jar verified.')
bundle_cert,_ = capture(java_home+'/bin/keytool','-printcert','-jarfile',paths[:aab])
raise 'AAB upload certificate mismatch' unless bundle_cert[/SHA256:\s*([0-9A-F:]+)/,1].to_s.delete(':').downcase==expected_cert
report[:android] = {package:'app.cool.mobile',version:'1.2.4',build:23,receive_sms:true,read_sms:false,
  upload_certificate_sha256:'9ee12172c78a8a487906d9159bfdd17b4d78aba3541f17b410659e6d60ddcc10',
  signature_verification:'APK v2 and AAB JAR independently verified; expected self-signed Android upload certificate'}
Dir.mktmpdir('collect-ipa-readback-') do |dir|
  capture('/usr/bin/ditto','-x','-k',paths[:ipa],dir)
  app = File.join(dir,'Payload/Collect.app')
  capture('/usr/bin/codesign','--verify','--deep','--strict',app)
  info = JSON.parse(capture('/usr/bin/plutil','-convert','json','-o','-',File.join(app,'Info.plist')).first)
  entitlements,_err = capture('/usr/bin/codesign','-d','--entitlements',':-',app)
  ent_json,err,status = Open3.capture3('/usr/bin/plutil','-convert','json','-o','-','--','-',stdin_data:entitlements)
  raise 'Cannot decode signing entitlements' unless status.success?
  ent = JSON.parse(ent_json)
  raise 'iOS package/version mismatch' unless info['CFBundleIdentifier']=='app.cool.mobile' && info['CFBundleShortVersionString']=='1.2.4' && info['CFBundleVersion']=='23'
  raise 'iOS development entitlement in exported IPA' unless ent['get-task-allow']==false
  raise 'iOS production push entitlement missing' unless ent['aps-environment']=='production'
  raise 'Unexpected iOS signing application identity' unless ent['application-identifier']=='63STJ5N27W.app.cool.mobile'
  binary = File.binread(File.join(app,'Frameworks/App.framework/App'))
  raise 'Packaged production backend missing' unless binary.include?('https://lhbowpbcpwoiparwnwgt.supabase.co')
  report[:ios] = {strict_signature:'pass',bundle:info['CFBundleIdentifier'],version:info['CFBundleShortVersionString'],
    build:info['CFBundleVersion'],minimum_os:info['MinimumOSVersion'],get_task_allow:ent['get-task-allow'],
    aps_environment:ent['aps-environment'],production_backend_embedded:true,
    privacy_manifest_count:Dir[File.join(app,'**/PrivacyInfo.xcprivacy')].length}
end
report[:source] = {branch:'main',git_commit_created:false,files:[]}
Dir[File.join(ROOT,'lib/**/*.dart'),File.join(ROOT,'supabase/functions/**/*.ts'),File.join(ROOT,'supabase/migrations/*.sql'),
    File.join(ROOT,'pubspec.yaml'),File.join(ROOT,'pubspec.lock')].sort.each do |path|
  report[:source][:files] << {path:path.delete_prefix(ROOT+'/'),sha256:Digest::SHA256.file(path).hexdigest}
end
report[:result] = 'SIGNED_NATIVE_ARTIFACTS_VALIDATED_NOT_DISTRIBUTED'
File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(report)+"\n") }
puts JSON.pretty_generate(report.reject { |key,_|key==:source })
