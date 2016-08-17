require 'resque_starter/version'

class ResqueStarter::Config
  def initialize(config_file)
    @config_file = config_file
    # TIPS: resque worker ENV configuration
    # self.verbose = ENV['LOGGING'] || ENV['VERBOSE']
    # self.very_verbose = ENV['VVERBOSE']
    # self.term_timeout = ENV['RESQUE_TERM_TIMEOUT'] || 4.0
    # self.term_child = ENV['TERM_CHILD']
    # self.graceful_term = ENV['GRACEFUL_TERM']
    # self.run_at_exit_hooks = ENV['RUN_AT_EXIT_HOOKS']
    reload
  end

  def reload
    @set = Hash.new
    @set[:concurrency] = 1
    @set[:dequeue_interval] = 5.0
    instance_eval(File.read(@config_file), @config_file)
  end

  %i[
    concurrency
    log_file
    pid_file
    status_file
    preload_app
    queues
    dequeue_interval
  ].each do |name|
    define_method(name) do |val|
      if val
        @set[name] = val
      else
        @set[name]
      end
    end
  end

  def [](key)
    @set[key]
  end

  def before_fork(&block)
    if block_given?
      @set[:before_fork] = block
    else
      @set[:before_fork]
    end
  end

  def after_fork(&block)
    if block_given?
      @set[:after_fork] = block
    else
      @set[:after_fork]
    end
  end
end
