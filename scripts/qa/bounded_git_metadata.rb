# frozen_string_literal: true

# Git metadata is descriptive. A blocked recovery volume must not turn a
# website build into an unbounded process or a false clean-worktree claim.
module BoundedGitMetadata
  module_function

  def capture(argv, root:, seconds:, output_limit: 262_144)
    reader, writer = IO.pipe
    pid = Process.spawn(*argv, chdir: root, in: File::NULL, out: writer,
                        err: File::NULL, pgroup: true)
    writer.close
    output = +''.b
    status = nil
    error = nil
    eof = false
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      begin
        output << reader.read_nonblock(8192) unless eof
        if output.bytesize > output_limit
          error = 'output_limit'
          break
        end
      rescue IO::WaitReadable
        # Wait below without blocking process-exit or deadline checks.
      rescue EOFError
        eof = true
      end
      status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
      break if status && eof
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if remaining <= 0
        error = 'deadline'
        break
      end
      IO.select(eof ? [] : [reader], nil, nil, [remaining, 0.02].min)
    end
    { 'output' => output, 'success' => error.nil? && status&.success? == true,
      'error' => error || (status&.success? ? nil : 'command_failed'), 'pid' => pid }
  rescue SystemCallError, IOError => exception
    { 'output' => '', 'success' => false, 'error' => exception.class.name, 'pid' => pid }
  ensure
    # Signal only the process group created above. Reaping is nonblocking;
    # even an uninterruptible filesystem read cannot block the build here.
    if pid && (!status || error)
      %w[TERM KILL].each do |signal|
        begin
          Process.kill(signal, -pid)
        rescue Errno::ESRCH
          break
        end
        status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
      rescue Errno::ECHILD
        break
      end
      Process.detach(pid) unless status
    end
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  def observe(root)
    commit = capture(['git', '-C', root, 'rev-parse', 'HEAD'], root: root, seconds: 3)
    state = capture(['git', '-C', root, 'status', '--porcelain'], root: root, seconds: 10)
    revision = commit['output'].strip
    {
      'source_commit' => commit['success'] && /\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z/.match?(revision) ? revision : nil,
      'source_dirty' => !state['success'] || !state['output'].empty?,
      'source_git_status' => state['success'] ? 'observed' : 'unavailable',
      'source_git_status_error' => state['error']
    }
  end
end
