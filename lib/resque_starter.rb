require 'resque'
require 'resque_starter/version'
require 'resque_starter/config'

class ResqueStarter
  attr_reader :config

  def initialize(config_file)
    @config = ResqueStarter::Config.new(config_file)

    @old_workers = {}
    @num_workers = config[:concurrency]
    @self_read, @self_write = IO.pipe

    # open pid file
    if config[:pid_file]
      File.open(config[:pid_file], "w") do |fh|
        fh.puts $$
      end rescue abort "failed to open file:#{config[:pid_file]}"
      at_exit { File.unlink config[:pid_file] rescue nil }
    end

    # open log file
    if config[:log_file]
      File.open(config[:log_file], "a") do |fh|
        $stdout.flush
        $stderr.flush
        $stdout.reopen(fh) rescue abort "failed to reopen STDOUT to file"
        $stderr.reopen(fh) rescue abort "failed to reopen STDERR to file"
      end
    end

    # create guard that removes the status file
    if config[:status_file]
      at_exit { File.unlink config[:status_file] rescue nil }
    end
  end

  def start_resque
    $stderr.puts "starting resque starter (master) #{Process.pid}"
    preload if config[:preload_app]
    maintain_worker_count

    install_signal_handler
    @handle_thr = start_handle_thread
    while true
      break unless @handle_thr.alive? # dies if @shutdown and @old_workers.empty?
      begin
        pid, status = Process.waitpid2(-1)
        $stderr.puts "worker #{pid} died, status:#{status.exitstatus}"
        @self_write.puts(pid)
      rescue Errno::ECHILD
        @handle_thr.kill if @shutdown # @old_workers should be empty
        sleep 0.1 # avoid busy loop for no child by TTOU
      end
    end

    $stderr.puts "shutting down resque starter (master) #{Process.pid}"
  end

  def install_signal_handler
    %w(TERM INT QUIT USR1 USR2 CONT TTIN TTOU).each do |sig|
      trap(sig) { @self_write.puts(sig) }
    end
  end

  def start_handle_thread
    Thread.new {
      while readable_io = IO.select([@self_read])
        s = readable_io.first[0].gets.strip
        if pid = (Integer(s) rescue nil)
          handle_waitpid2(pid)
        else
          handle_signal(s)
        end
      end
    }
  end

  def handle_waitpid2(pid)
    @old_workers.delete(pid)
    if @shutdown
      @handle_thr.kill if @old_workers.empty?
    else
      maintain_worker_count
    end
  end

  # Resque starter (master process) responds to a few different signals:
  # * TERM / INT - Quick shutdown, kills all workers immediately then exit
  # * QUIT - Graceful shutdown, waits for workers to finish processing then exit
  # * USR1 - Send USR1 to all workers, which immediately kill worker's child but don't exit
  # * USR2 - Send USR2 to all workers, which don't start to process any new jobs
  # * CONT - Send CONT to all workers, which start to process new jobs again after a USR2
  # * TTIN - Increment the number of worker processes by one
  # * TTOU - Decrement the number of worker processes by one with QUIT
  def handle_signal(sig)
    pids = @old_workers.keys.sort
    msg = "received #{sig}, "

    # Resque workers respond to a few different signals:
    # * TERM / INT - Immediately kill child then exit
    # * QUIT - Wait for child to finish processing then exit
    # * USR1 - Immediately kill child but don't exit
    # * USR2 - Don't start to process any new jobs
    # * CONT - Start to process new jobs again after a USR2
    case sig
    when 'TERM', 'INT' 
      $stderr.puts msg << "immediately kill all workers then exit:#{pids.join(',')}"
      @shutdown = true
      Process.kill(sig, *pids)
    when 'QUIT'
      $stderr.puts msg << "wait for all workers to finish processing then exit:#{pids.join(',')}"
      @shutdown = true
      Process.kill(sig, *pids)
    when 'USR1'
      $stderr.puts msg << "immediately kill the child of all workers:#{pids.join(',')}"
      Process.kill(sig, *pids)
    when 'USR2'
      $stderr.puts msg << "don't start to process any new jobs:#{pids.join(',')}"
      Process.kill(sig, *pids)
    when 'CONT'
      $stderr.puts msg << "start to process new jobs again after USR2:#{pids.join(',')}"
      Process.kill(sig, *pids)
    when 'TTIN'
      @num_workers += 1
      $stderr.puts msg << "increment the number of workers:#{@num_workers}"
      maintain_worker_count # ToDo: forking from a thread would be unsafe
    when 'TTOU'
      @num_workers -= 1 if @num_workers > 0
      $stderr.puts msg << "decrement the number of workers:#{@num_workers}"
      maintain_worker_count
    end
  rescue Errno::ESRCH
  rescue
    abort
  end

  def maintain_worker_count
    return if (off = @old_workers.size - @num_workers) == 0
    return spawn_missing_workers if off < 0
    @old_workers.dup.each_pair {|pid, nr|
      if nr >= @num_workers
        Process.kill(:QUIT, pid) rescue nil
      end
    }
  end

  def spawn_missing_workers
    worker_nr = -1
    until (worker_nr += 1) == @num_workers
      next if @old_workers.value?(worker_nr)
      worker = Resque::Worker.new(*(config[:queues]))
      config[:before_fork].call(self, worker)
      if pid = fork
        @old_workers[pid] = worker_nr
        $stderr.puts "starting new worker #{pid}"
      else # child
        config[:after_fork].call(self, worker)
        worker.work(config[:dequeue_interval])
        exit
      end
    end
  rescue => e
    abort
  end

  def preload
    if defined?(Rails) && Rails.respond_to?(:application)
      # Rails 3
      Rails.application.eager_load!
    elsif defined?(Rails::Initializer)
      # Rails 2.3
      $rails_rake_task = false
      Rails::Initializer.run :load_application_classes
    end
  end
end
