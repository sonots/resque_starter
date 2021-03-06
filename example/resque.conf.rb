# Number of concurrency (resque workers)
concurrency 2

# By default, resque_starter logs to stdout
# logger ::Logger.new(::File.expand_path('../../tmp/log/resque_starter.log', __FILE__))
# logger.level = ::Logger::INFO
# logger.formatter = ResqueStarter::Logger::Formatter.new

# Stores pid for resque starter (master) itself
pid_file ::File.expand_path('../../tmp/pids/resque_starter.pid', __FILE__)

# Status file stores pids of resque workers, etc
status_file ::File.expand_path('../../tmp/pids/resque_starter.stat', __FILE__)

# Watching queues of resque workers in priority orders
# Same with QUEUES environment variables for rake resque:work
# See https://github.com/resque/resque#priorities-and-queue-lists
#
# Default obtains from @queue class instance variables of worker class
# See https://github.com/resque/resque#overview
queues ['high', 'low']

# Polling frequency (default: 5)
# Same with INTERVAL environment variables for rake resque:work
# See https://github.com/resque/resque#polling-frequency
dequeue_interval 0.1

# Preload rails application codes before forking to save memory by CoW
# require ::File.expand_path('../../config/environment', __FILE__)
# Rails.application.eager_load!

before_fork do |starter, worker, worker_nr|
  # the following is highly recomended for Rails + "preload_app true"
  # as there's no need for the master process to hold a connection
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
end

after_fork do |starter, worker, worker_nr|
  # the following is *required* for Rails + "preload_app true",
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection
end
