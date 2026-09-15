# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'openssl'
require 'securerandom'
require 'uri'
require_relative 'fullstack_database_sql'

# One PostgREST process against a disposable current-schema copy. No hosted
# URL, existing API container, user-selected database or shared JWT is accepted.
module FullstackDatabaseHttp
  DATABASE = 'collect_fullstack_http_20260914'.freeze
  CONTAINER = "collect_http_#{FullstackDatabase::PROJECT}".freeze
  IMAGE = 'public.ecr.aws/supabase/postgrest:v16.1'.freeze
  REPLAY = File.join(FullstackDatabase::ROOT, '.cache/fullstack-qa/20260914T151002Z/database-current-replay-chain-126.json').freeze
  PUBLIC_ENV = {
    'PGRST_DB_ANON_ROLE' => 'anon', 'PGRST_DB_SCHEMAS' => 'public',
    'PGRST_DB_EXTRA_SEARCH_PATH' => 'public,extensions', 'PGRST_DB_MAX_ROWS' => '1000',
    'PGRST_DB_POOL' => '5', 'PGRST_DB_POOL_ACQUISITION_TIMEOUT' => '5'
  }.freeze

  def self.validate!(container, run_id:, image_id:, jwt_secret:, allow_stopped: false)
    config = container.fetch('Config')
    labels = config['Labels'] || {}
    state = container.fetch('State')
    running = state['Running'] == true && !state['Paused'] && !state['Restarting'] && !state['Dead']
    stopped = allow_stopped && state['Running'] == false && %w[created exited].include?(state['Status']) &&
      !state['Paused'] && !state['Restarting'] && !state['Dead']
    unless container['Name'] == "/#{CONTAINER}" && labels['collect.qa.task'] == FullstackDatabase::TASK &&
           labels['collect.qa.run'] == run_id && labels['collect.qa.purpose'] == 'runtime_http' && (running || stopped)
      raise 'Exact task/run-owned API container required'
    end
    raise 'Pinned local API image required' unless container['Image'] == image_id && config['Image'] == image_id
    env = config.fetch('Env').to_h { |entry| entry.split('=', 2) }
    uri = URI(env.fetch('PGRST_DB_URI'))
    unless %w[postgres postgresql].include?(uri.scheme) && uri.host == FullstackDatabase::CONTAINER &&
           uri.port == 5432 && uri.path == "/#{DATABASE}" && uri.user == 'authenticator' &&
           !uri.password.to_s.empty? && !uri.query && !uri.fragment &&
           env['PGRST_JWT_SECRET'] == jwt_secret && PUBLIC_ENV.all? { |key, value| env[key] == value }
      raise 'Task database, fresh test JWT and configured public schema required'
    end
    unless container.dig('NetworkSettings', 'Networks')&.keys == [FullstackDatabase::NETWORK] &&
           container.dig('HostConfig', 'ReadonlyRootfs') == true &&
           container.fetch('Mounts').empty? && container.dig('HostConfig', 'CapDrop') == ['ALL'] &&
           container.dig('HostConfig', 'SecurityOpt')&.include?('no-new-privileges')
      raise 'API must use only the owned internal network and a read-only filesystem'
    end
    ports = container.dig('HostConfig', 'PortBindings') || {}
    live_ports = container.dig('NetworkSettings', 'Ports') || {}
    raise 'No host API port may be published' unless ports.empty? && live_ports.values.all? { |bindings| bindings.nil? || bindings.empty? }
    {
      container: CONTAINER, container_id: container.fetch('Id'), image: IMAGE, image_id: image_id,
      task_id: FullstackDatabase::TASK, run_id: run_id, database: DATABASE,
      network: FullstackDatabase::NETWORK, endpoint: running ? "http://#{CONTAINER}:3000" : nil,
      transport: 'curl_inside_task_database_container_over_owned_internal_network',
      api_config: PUBLIC_ENV, running: running, state: state['Status'], credentials_recorded: false
    }
  end

  class Session
    attr_reader :report, :directory, :endpoint

    def initialize(directory)
      raise 'New API evidence directory required' if File.exist?(directory)
      @directory = File.expand_path(directory)
      Dir.mkdir(@directory, 0o700)
      @run_id = File.basename(@directory) + '-' + SecureRandom.hex(8)
      @jwt_secret = SecureRandom.hex(32)
      @report = { started_at: Time.now.utc.iso8601(6), final_acceptance: false,
                  run_id: @run_id, requests: [], lifecycle: [],
                  limitations: ['PostgREST with synthetic JWTs and sessions; not GoTrue/OTP, Kong, Edge, native or hosted acceptance',
                                'Scheduled/network database workers are disabled; no external message/provider transport'] }
      @database_created = false
      @api_creation_attempted = false
      @api_id = nil
      @command_number = 0
    end

    def record!
      File.open(File.join(@directory, 'report.json'), File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(JSON.pretty_generate(@report) + "\n")
      end
    end

    def command(*args, input: nil, timeout: 45)
      out, err, status = FullstackDatabase.docker(*args, input: input, timeout: timeout)
      raise "Local API command failed: #{redact(err).lines.first}" unless status.success?
      out
    end

    def sql(input, label: nil)
      FullstackDatabase.verify!
      @command_number += 1
      name = label || "sql-#{@command_number}"
      raise 'Simple SQL evidence label required' unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
      path = File.join(@directory, "#{name}.sql")
      raise 'New SQL evidence name required' if File.exist?(path)
      sql = "set statement_timeout='30s'; set lock_timeout='5s';\n#{input}"
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(sql) }
      out, err, status = FullstackDatabase.docker('exec', '-i', FullstackDatabase::CONTAINER,
        'psql', '-XqAt', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', input: sql, timeout: 45)
      File.write(File.join(@directory, "#{name}.log"), redact(out + err))
      raise "Local API fixture SQL failed: #{redact(err).lines.first}" unless status.success?
      out
    rescue FullstackDatabase::CommandTimeout => error
      File.write(File.join(@directory, "#{name}.log"), redact(error.output + error.error))
      raise
    end

    def start!
      state = FullstackDatabaseSql.verified_baseline(replay_report: REPLAY)
      @report[:database_target] = state[:target]
      @report[:baseline_before] = state[:baseline]
      @report[:migration_sources] = state[:expected]
      @report[:replay_report_sha256] = Digest::SHA256.file(REPLAY).hexdigest
      # Pinned image must already exist; this review never pulls an image.
      image = JSON.parse(FullstackDatabase.capture('image', 'inspect', IMAGE)).fetch(0)
      @image_id = image.fetch('Id')
      @report[:image_id] = @image_id
      existing = FullstackDatabase.capture('container', 'ls', '--all', '--filter', "name=^/#{CONTAINER}$", '--format', '{{.ID}}')
      raise 'Refusing an existing API container' unless existing.strip.empty?
      worker_config = FullstackDatabaseSql.execute!('psql', '-XqAt', '-U', 'postgres', '-d', 'postgres',
        '-v', 'ON_ERROR_STOP=1', input: "select current_setting('shared_preload_libraries');").strip
      raise 'Scheduled/network workers must remain disabled' if worker_config.split(',').any? { |name| %w[pg_cron pg_net].include?(name.strip) }
      @report[:preload] = worker_config
      command('exec', FullstackDatabase::CONTAINER, 'createdb', '-U', 'postgres', '--template=postgres', DATABASE)
      @database_created = true
      @report[:lifecycle] << { event: 'fresh_database_copy_created', database: DATABASE }

      raw = JSON.parse(FullstackDatabase.capture('inspect', state[:target][:container_id])).fetch(0)
      db_env = raw.fetch('Config').fetch('Env').to_h { |entry| entry.split('=', 2) }
      password = db_env.fetch('POSTGRES_PASSWORD')
      raise 'Invalid local password encoding' if password.include?("\n") || password.empty?
      encoded_password = URI.encode_www_form_component(password).gsub('+', '%20')
      @db_uri = "postgresql://authenticator:#{encoded_password}@#{FullstackDatabase::CONTAINER}:5432/#{DATABASE}"
      private_dir = File.join(@directory, 'private')
      Dir.mkdir(private_dir, 0o700)
      env_path = File.join(private_dir, 'api.env')
      values = PUBLIC_ENV.merge('PGRST_DB_URI' => @db_uri, 'PGRST_JWT_SECRET' => @jwt_secret)
      File.open(env_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| values.each { |key, value| file.puts("#{key}=#{value}") } }
      @api_creation_attempted = true
      @api_id = command('create', '--pull=never', '--init', '--name', CONTAINER,
        '--label', "collect.qa.task=#{FullstackDatabase::TASK}", '--label', "collect.qa.run=#{@run_id}",
        '--label', 'collect.qa.purpose=runtime_http', '--network', FullstackDatabase::NETWORK,
        '--read-only', '--cap-drop=ALL',
        '--security-opt', 'no-new-privileges', '--env-file', env_path, @image_id).strip
      @report[:lifecycle] << { event: 'owned_api_created', container_id: @api_id }
      command('start', @api_id)
      target = verify!
      @endpoint = target[:endpoint]
      @report[:api_target] = target
      @report[:status] = 'ready_for_http_probe'
      record!
      self
    rescue StandardError => error
      @report[:status], @report[:error] = 'fail', redact(error.message)
      if error.is_a?(FullstackDatabase::CommandTimeout)
        @report[:timeout_stdout], @report[:timeout_stderr] = redact(error.output), redact(error.error)
      end
      record!
      raise
    end

    def verify!(allow_stopped: false)
      FullstackDatabase.verify!
      raw = JSON.parse(FullstackDatabase.capture('inspect', CONTAINER)).fetch(0)
      raise 'API container identity changed' unless raw['Id'] == @api_id
      FullstackDatabaseHttp.validate!(raw, run_id: @run_id, image_id: @image_id,
        jwt_secret: @jwt_secret, allow_stopped: allow_stopped)
    end

    def token(claims, secret: @jwt_secret, header: { alg: 'HS256', typ: 'JWT' })
      encode = ->(value) { Base64.urlsafe_encode64(JSON.generate(value), padding: false) }
      unsigned = encode.call(header) + '.' + encode.call(claims)
      unsigned + '.' + Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', secret, unsigned), padding: false)
    end

    def request(label, path, body: nil, jwt: nil, method: nil, headers: {})
      raise 'Verified task-internal endpoint required' unless @endpoint == "http://#{CONTAINER}:3000"
      raise 'Relative API path required' unless path.start_with?('/') && !path.start_with?('//')
      verb = method || (body ? 'POST' : 'GET')
      raise 'Unsupported HTTP method' unless %w[GET POST PATCH DELETE].include?(verb)
      request_headers = { 'Content-Type' => 'application/json' }.merge(headers)
      request_headers['Authorization'] = 'Bearer ' + jwt if jwt
      config = +"url = #{JSON.generate(@endpoint + path)}\nrequest = #{JSON.generate(verb)}\n"
      request_headers.each { |key, value| config << "header = #{JSON.generate(key+': '+value)}\n" }
      config << "data = #{JSON.generate(JSON.generate(body))}\n" unless body.nil?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # JWTs are passed on stdin, never command arguments, logs, or files.
      # No redirects/proxies and no published host port are used.
      out, err, status = FullstackDatabase.docker('exec', '-i', FullstackDatabase::CONTAINER,
        'curl', '--silent', '--show-error', '--noproxy', '*', '--proxy', '', '--connect-timeout', '2',
        '--max-time', '10', '--include', '--config', '-', input: config, timeout: 15)
      raise IOError, "Internal HTTP transport failed: #{redact(err)}" unless status.success?
      head, text = out.split("\r\n\r\n", 2)
      raise IOError, 'HTTP response missing header/body boundary' unless text
      response_code = head.lines.first.split[1].to_i
      response_headers = head.lines.drop(1).map do |line|
        key, value = line.strip.split(':', 2)
        [key.downcase, value.strip] if value
      end.compact.to_h
      parsed = text.empty? ? nil : (JSON.parse(text) rescue nil)
      @report[:requests] << {
        label: label, path: path, method: verb, http_status: response_code,
        seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(4),
        response: parsed, body_sha256: Digest::SHA256.hexdigest(text),
        content_type: response_headers['content-type'], server: response_headers['server'],
        authorization_recorded: false
      }
      record!
      [response_code, parsed]
    rescue IOError, EOFError, SystemCallError, FullstackDatabase::CommandTimeout => error
      @report[:requests] << { label: label, path: path, status: 'transport_error', error: redact(error.message),
                              authorization_recorded: false }
      record!
      raise
    end

    def finish!
      errors = []
      if @api_id
        begin
          target = verify!(allow_stopped: true)
          if target[:running]
            command('stop', '--timeout', '10', target[:container_id], timeout: 20)
            raise 'API is still running after stop' if verify!(allow_stopped: true)[:running]
          end
          out, err, status = FullstackDatabase.docker('logs', '--tail', '200', target[:container_id], timeout: 15)
          File.write(File.join(@directory, 'api.log'), redact(out + err))
          raise 'API log capture failed' unless status.success?
          command('rm', target[:container_id])
          @report[:lifecycle] << { event: 'owned_api_removed', container_id: @api_id }
          File.unlink(File.join(@directory, 'private/api.env'))
          @report[:lifecycle] << { event: 'ephemeral_credential_file_removed' }
        rescue StandardError => error
          errors << redact(error.message)
        end
      elsif @api_creation_attempted
        errors << 'API creation outcome is unverified; database retained pending exact task/run identity readback'
      end
      if @database_created && errors.empty?
        begin
          FullstackDatabase.verify!
          command('exec', FullstackDatabase::CONTAINER, 'dropdb', '-U', 'postgres', DATABASE)
          @report[:lifecycle] << { event: 'created_database_copy_removed', database: DATABASE }
          @report[:baseline_after] = FullstackDatabaseSql.readback('postgres')
          raise 'Original bootstrap baseline changed' unless @report[:baseline_after] == @report[:baseline_before]
        rescue StandardError => error
          errors << redact(error.message)
        end
      end
      @report[:cleanup_errors] = errors
      @report[:status] = 'fail' unless errors.empty?
      @report[:finished_at] = Time.now.utc.iso8601(6)
      record!
      errors.empty?
    end

    def redact(value)
      text = value.to_s.gsub(/postgres(?:ql)?:\/\/\S+/, '[LOCAL_DB_URI]')
      text.gsub(@jwt_secret, '[TEST_JWT_SECRET]')
    end
  end
end
