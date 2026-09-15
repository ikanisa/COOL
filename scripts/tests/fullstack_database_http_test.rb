# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'securerandom'
require_relative '../qa/fullstack_database_http'
require_relative 'fullstack_api_uat'

class FullstackDatabaseHttpTest < Minitest::Test
  HTTP = FullstackDatabaseHttp

  def password
    @password ||= SecureRandom.hex(24)
  end

  def database_uri(user: 'authenticator', host: FullstackDatabase::CONTAINER, database: HTTP::DATABASE)
    # The fixture is never connected. Construct credentials at runtime so the
    # repository retains no password-bearing URL, including test examples.
    "postgresql://#{user}:#{password}@#{host}:5432/#{database}"
  end

  def fixture
    {
      'Id' => 'exact-owned-id', 'Name' => "/#{HTTP::CONTAINER}", 'Image' => 'sha256:pinned',
      'Config' => { 'Image' => 'sha256:pinned',
        'Labels' => { 'collect.qa.task' => FullstackDatabase::TASK, 'collect.qa.run' => 'test-run',
                      'collect.qa.purpose' => 'runtime_http' },
        'Env' => HTTP::PUBLIC_ENV.merge('PGRST_JWT_SECRET' => 'test-secret',
          'PGRST_DB_URI' => database_uri).map { |k,v| "#{k}=#{v}" } },
      'State' => { 'Running' => true, 'Status' => 'running', 'Paused' => false, 'Restarting' => false, 'Dead' => false },
      'NetworkSettings' => { 'Networks' => { FullstackDatabase::NETWORK => {} },
                             'Ports' => { '3000/tcp' => nil } },
      'HostConfig' => { 'ReadonlyRootfs' => true, 'CapDrop' => ['ALL'], 'SecurityOpt' => ['no-new-privileges'],
                        'PortBindings' => {} },
      'Mounts' => []
    }
  end

  def validate(value, **options)
    HTTP.validate!(value, run_id: 'test-run', image_id: 'sha256:pinned', jwt_secret: 'test-secret', **options)
  end

  def test_exact_target_accepts_and_returns_only_public_provenance
    result = validate(fixture)
    assert_equal "http://#{HTTP::CONTAINER}:3000", result[:endpoint]
    refute_includes JSON.generate(result), password
    refute_includes JSON.generate(result), 'test-secret'
    assert_equal false, result[:credentials_recorded]
  end

  def test_identity_and_task_run_labels_must_match
    %w[collect.qa.task collect.qa.run collect.qa.purpose].each do |key|
      value = fixture
      value['Config']['Labels'][key] = 'unrelated'
      assert_raises(RuntimeError) { validate(value) }
    end
    value = fixture
    value['Name'] = '/unrelated'
    assert_raises(RuntimeError) { validate(value) }
    value = fixture
    value['Image'] = 'sha256:changed'
    assert_raises(RuntimeError) { validate(value) }
  end

  def test_database_role_target_schema_and_secret_cannot_change
    replacements = {
      'PGRST_DB_URI' => [database_uri(host: 'hosted.example'),
                        database_uri(user: 'postgres'),
                        database_uri(database: 'postgres')],
      'PGRST_JWT_SECRET' => ['another-secret'], 'PGRST_DB_SCHEMAS' => ['public,auth'],
      'PGRST_DB_ANON_ROLE' => ['service_role']
    }
    replacements.each do |key, alternatives|
      alternatives.each do |replacement|
        value = fixture
        value['Config']['Env'].map! { |entry| entry.start_with?(key+'=') ? key+'='+replacement : entry }
        assert_raises(RuntimeError) { validate(value) }
      end
    end
  end

  def test_container_cannot_publish_publicly_or_reach_another_network
    [false, true].each do |live|
      value = fixture
      bindings = live ? value['NetworkSettings']['Ports'] : value['HostConfig']['PortBindings']
      bindings['3000/tcp'] = [{ 'HostIp' => '127.0.0.1', 'HostPort' => '55445' }]
      assert_raises(RuntimeError) { validate(value) }
    end
    value = fixture
    value['HostConfig']['PortBindings']['3001/tcp'] = []
    assert_raises(RuntimeError) { validate(value) }
    value = fixture
    value['NetworkSettings']['Networks']['bridge'] = {}
    assert_raises(RuntimeError) { validate(value) }
  end

  def test_filesystem_and_capability_isolation_required
    value = fixture
    value['HostConfig']['ReadonlyRootfs'] = false
    assert_raises(RuntimeError) { validate(value) }
    value = fixture
    value['Mounts'] = [{ 'RW' => false, 'Type' => 'bind' }]
    assert_raises(RuntimeError) { validate(value) }
    value = fixture
    value['HostConfig']['CapDrop'] = []
    assert_raises(RuntimeError) { validate(value) }
  end

  def test_inactive_state_is_explicit_and_still_rejects_bad_states
    %w[created exited].each do |state|
      value = fixture
      value['State'].merge!('Running' => false, 'Status' => state)
      assert_raises(RuntimeError) { validate(value) }
      assert_nil validate(value, allow_stopped: true)[:endpoint]
      value['State']['Dead'] = true
      assert_raises(RuntimeError) { validate(value, allow_stopped: true) }
    end
  end

  def test_uncertain_api_creation_preserves_database_and_reports_failure
    Dir.mktmpdir do |dir|
      session = HTTP::Session.new(File.join(dir, 'run'))
      session.instance_variable_set(:@api_creation_attempted, true)
      session.instance_variable_set(:@database_created, true)
      session.stub(:command, ->(*_args) { flunk 'No removal is safe before creation identity is resolved' }) do
        refute session.finish!
      end
      assert_equal 'fail', session.report[:status]
      assert_match(/unverified/, session.report[:cleanup_errors].first)
    end
  end

  def test_sql_timeout_retains_partial_output
    Dir.mktmpdir do |dir|
      session = HTTP::Session.new(File.join(dir, 'run'))
      failure = FullstackDatabase::CommandTimeout.new('partial statement', 'partial diagnostic', 45)
      FullstackDatabase.stub(:verify!, {}) do
        FullstackDatabase.stub(:docker, ->(*_args, **_opts) { raise failure }) do
          assert_raises(FullstackDatabase::CommandTimeout) { session.sql('select 1;', label: 'timeout') }
        end
      end
      log = File.read(File.join(dir, 'run/timeout.log'))
      assert_includes log, 'partial statement'
      assert_includes log, 'partial diagnostic'
    end
  end

  def test_real_http_response_parsing_and_stdin_only_authorization
    Dir.mktmpdir do |dir|
      session = HTTP::Session.new(File.join(dir, 'run'))
      session.instance_variable_set(:@endpoint, "http://#{HTTP::CONTAINER}:3000")
      status = Struct.new(:success?).new(true)
      transport = lambda do |*args, **options|
        refute_includes args.join(' '), 'sensitive-test-token'
        assert_includes options.fetch(:input), 'Authorization: Bearer sensitive-test-token'
        assert_includes args, '--noproxy'
        ["HTTP/1.1 403 Forbidden\r\nContent-Type: application/json; charset=utf-8\r\nServer: postgrest/16.1\r\n\r\n{\"code\":\"42501\"}", '', status]
      end
      FullstackDatabase.stub(:docker, transport) do
        code, body = session.request('protected', '/rpc/admin_current_user', body: {}, jwt: 'sensitive-test-token')
        assert_equal 403, code
        assert_equal '42501', body['code']
      end
      report = File.read(File.join(dir, 'run/report.json'))
      refute_includes report, 'sensitive-test-token'
      assert_equal 'postgrest/16.1', session.report[:requests].first[:server]
    end
  end

  def test_http_client_timeout_is_recorded_as_transport_error
    Dir.mktmpdir do |dir|
      session = HTTP::Session.new(File.join(dir, 'run'))
      session.instance_variable_set(:@endpoint, "http://#{HTTP::CONTAINER}:3000")
      transport = ->(*_args, **_options) { raise FullstackDatabase::CommandTimeout.new('', 'timeout', 15) }
      FullstackDatabase.stub(:docker, transport) do
        assert_raises(FullstackDatabase::CommandTimeout) { session.request('timeout', '/rpc/admin_current_user', body: {}) }
      end
      assert_equal 'transport_error', session.report[:requests].first[:status]
      assert File.exist?(File.join(dir, 'run/report.json'))
    end
  end

  def test_denial_requires_privilege_sqlstate_or_exact_legacy_permission_error
    runner = FullstackApiUat.allocate
    examples = [
      [[403, { 'code' => '42501', 'message' => 'permission denied' }], true],
      [[400, { 'code' => 'P0001', 'message' => 'Admin permission admin_users.read required' }], true],
      [[400, { 'code' => '22023', 'message' => 'invalid UUID' }], false],
      [[400, { 'code' => 'P0001', 'message' => 'Account unavailable' }], false],
      [[404, { 'code' => 'PGRST202', 'message' => 'RPC not found' }], false]
    ]
    examples.each do |result, expected|
      runner.stub(:check, ->(_label, permitted, _status) { assert_equal expected, permitted }) do
        runner.denied('test', result)
      end
    end
  end
end
