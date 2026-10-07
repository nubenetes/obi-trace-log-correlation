# frozen_string_literal: true

require 'json'
require 'time'

# OBI Trace-Log Correlation Ruby Demo Application
# Demonstrates:
# 1. Working Mode: STDOUT.sync = true ensures unbuffered synchronous write() syscalls
# 2. Broken Mode: STDOUT.sync = false causes libc 8 KiB block buffering on non-TTY pipes
# 3. Puma Clustered (Multi-Process) vs Multi-Threaded worker behavior

SYNC_STDOUT = ENV.fetch('RUBY_SYNC_STDOUT', 'true') == 'true'
STDOUT.sync = SYNC_STDOUT

def log_json(level, msg, extra = {})
  payload = {
    timestamp: Time.now.utc.iso8601,
    level: level,
    msg: msg,
    pid: Process.pid,
    thread_id: Thread.current.object_id,
    runtime: 'ruby-3.3-puma',
    stdout_sync: STDOUT.sync
  }.merge(extra)

  line = "#{JSON.generate(payload)}\n"

  # If STDOUT.sync is true, this triggers an immediate write(1, ...) syscall in the Linux kernel.
  # If STDOUT.sync is false, this buffers up to 8 KiB in user-space before flushing.
  $stdout.write(line)
end

log_json('INFO', 'Ruby application initialized', {
  mode: SYNC_STDOUT ? 'WORKING (STDOUT.sync = true)' : 'BROKEN (STDOUT.sync = false / Block Buffered)'
})

class App
  def call(env)
    path = env['PATH_INFO']
    method = env['REQUEST_METHOD']
    traceparent = env['HTTP_TRACEPARENT'] || 'none'

    case path
    when '/healthz'
      [200, { 'content-type' => 'text/plain' }, ["OK\n"]]
    when '/process'
      # OBI intercepts this write() syscall and correlates it with the incoming HTTP trace
      log_json('INFO', 'Processing Ruby transaction', {
        route: path,
        method: method,
        service: 'ruby-order-service',
        incoming_traceparent: traceparent
      })

      body = JSON.generate({
        status: 'success',
        platform: 'ruby-3.3',
        server: 'puma-clustered',
        worker_pid: Process.pid,
        thread_id: Thread.current.object_id,
        sync_mode: STDOUT.sync ? 'immediate_flush' : 'block_buffered'
      }) + "\n"

      [200, { 'content-type' => 'application/json' }, [body]]
    else
      [404, { 'content-type' => 'application/json' }, [JSON.generate({ error: 'not_found' }) + "\n"]]
    end
  end
end
