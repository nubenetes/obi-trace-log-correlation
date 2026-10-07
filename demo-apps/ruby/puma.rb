# frozen_string_literal: true

# Puma 6.x configuration for OBI Trace-Log Correlation demo

port ENV.fetch('PORT', 8085)
environment ENV.fetch('RACK_ENV', 'production')

# In clustered mode, workers are separate OS processes (each with its own PID).
# This gives OBI clean, dedicated process boundaries.
workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))

# Threads per worker process
threads_count = Integer(ENV.fetch('MAX_THREADS', 4))
threads threads_count, threads_count

preload_app!

on_worker_boot do
  # Crucial for Linux container log pipes: ensure each worker maintains unbuffered stdout
  STDOUT.sync = true if ENV.fetch('RUBY_SYNC_STDOUT', 'true') == 'true'
end
