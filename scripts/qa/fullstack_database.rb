# frozen_string_literal: true

require 'json'
require 'open3'

# This target is created for the 2026-09-14 review only. Never accepts a database
# URL, a user-selected container, a linked project or hosted credentials.
module FullstackDatabase
  ROOT = File.expand_path('../..', __dir__)
  TASK = '01a0a06a-73fb-7c23-81a6-36149a29e347'.freeze
  PROJECT = 'collect_fullstack_qa_20260914_01a0a06a'.freeze
  CONTAINER = "supabase_db_#{PROJECT}".freeze
  NETWORK = "supabase_network_#{PROJECT}".freeze
  WORKDIR = File.join(ROOT, '.cache/fullstack-qa/20260914T151002Z/database-target').freeze
  IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.158'.freeze

  class CommandTimeout < StandardError
    attr_reader :output, :error, :seconds

    def initialize(output, error, seconds)
      @output, @error, @seconds = output, error, seconds
      super("Local Docker client exceeded #{seconds}s; server-side outcome is unverified")
    end
  end

  # Bound transport as well as SQL execution. Terminate only this local CLI
  # process group; a timeout never proves that a daemon-side command stopped.
  def self.docker(*arguments, input: nil, timeout: 60)
    raise ArgumentError, 'Positive finite timeout required' unless
      timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
    output, error = +'', +''
    Open3.popen3('docker', *arguments, pgroup: true) do |stdin, stdout, stderr, waiter|
      readers = [[stdout, output], [stderr, error]].map do |io, buffer|
        Thread.new do
          begin
            loop { buffer << io.readpartial(16_384) }
          rescue EOFError
            nil
          end
        end
      end
      writer = Thread.new do
        begin
          stdin.write(input.to_s)
        rescue Errno::EPIPE, IOError
          nil # Early CLI failure is reported by its exit status and stderr.
        ensure
          stdin.close unless stdin.closed?
        end
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      workers = [writer, waiter, *readers]
      completed = workers.all? do |thread|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining.positive? && thread.join(remaining)
      end
      unless completed
        signal_client_group(waiter.pid, 'TERM')
        workers.each { |thread| thread.join(0.25) }
        signal_client_group(waiter.pid, 'KILL') if workers.any?(&:alive?)
        workers.each { |thread| thread.join(1) }
        raise CommandTimeout.new(output, error, timeout)
      end
      # Propagate reader/writer failures instead of treating incomplete output
      # as a successful inspection. All streams and the CLI met one deadline.
      [writer, *readers].each(&:value)
      [output, error, waiter.value]
    end
  end

  def self.signal_client_group(pid, signal)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end

  def self.capture(*arguments)
    output, error, status = docker(*arguments, timeout: 12)
    raise "Local Docker inspection failed: #{error.lines.first}" unless status.success?
    output
  end

  def self.validate!(container, network, endpoint, allow_stopped: false)
    raise 'Local Unix Docker socket required' unless endpoint.to_s.start_with?('unix:///')
    labels = container.dig('Config', 'Labels') || {}
    expected = {
      'com.supabase.cli.project' => PROJECT,
      'com.docker.compose.project' => PROJECT,
      'com.supabase.cli.workdir' => WORKDIR
    }
    state = container.fetch('State')
    permitted_state = !state['Paused'] && !state['Restarting'] && !state['Dead'] &&
      (state['Running'] == true ||
       (allow_stopped && state['Running'] == false && state['Status'] == 'exited'))
    unless expected.all? { |key, value| labels[key] == value } &&
           container['Name'] == "/#{CONTAINER}" && permitted_state
      raise 'Task-owned full-stack QA container in a permitted state required'
    end
    raise 'Unexpected database image' unless container.dig('Config', 'Image') == IMAGE
    unless container.dig('NetworkSettings', 'Networks')&.keys == [NETWORK] &&
           network['Name'] == NETWORK && network['Internal'] == true &&
           network.dig('Labels', 'collect.qa.task') == TASK
      raise 'Only the task-owned internal Docker network is permitted'
    end
    data_mounts = container.fetch('Mounts').select { |mount| mount['RW'] == true }
    unless data_mounts.length == 1 && data_mounts.first.values_at('Type', 'Name', 'Destination') ==
           ['volume', CONTAINER, '/var/lib/postgresql/data']
      raise 'Dedicated task database volume required; no other writable mounts permitted'
    end
    {
      container: CONTAINER, container_id: container.fetch('Id'),
      created_at: container.fetch('Created'), project: PROJECT, image: IMAGE,
      image_id: container.fetch('Image'), network: NETWORK,
      network_internal: true, task_id: TASK, workdir: WORKDIR,
      observed_running: state['Running'], observed_state: state['Status'],
      docker_endpoint_kind: 'local_unix_socket'
    }
  end

  def self.verify!(allow_stopped: false)
    # Docker gives an explicit context precedence over DOCKER_HOST.
    endpoint = ENV['DOCKER_HOST'] unless ENV.fetch('DOCKER_CONTEXT', '') != ''
    if endpoint.to_s.empty?
      endpoint = JSON.parse(capture('context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'))
    end
    raise 'Local Unix Docker socket required' unless endpoint.to_s.start_with?('unix:///')
    container = JSON.parse(capture('inspect', CONTAINER)).fetch(0)
    network = JSON.parse(capture('network', 'inspect', NETWORK)).fetch(0)
    validate!(container, network, endpoint, allow_stopped: allow_stopped)
  end
end
