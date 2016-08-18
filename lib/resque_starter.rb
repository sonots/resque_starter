require 'yaml'
require 'resque'
require 'resque_starter/version'
require 'resque_starter/config'
require 'resque_starter/logger'

class ResqueStarter
  attr_reader :config, :logger, :old_workers, :num_workers

  def initialize(config_file)
    @config = ResqueStarter::Config.new(config_file)

    @old_workers = {}
    @num_workers = config[:concurrency]
    @self_read, @self_write = IO.pipe

    # open pid file
    if config[:pid_file]
      begin
        File.open(config[:pid_file], "w") do |fh|
          fh.puts $$
        end
      rescue => e
        @logger.error "failed to open file:#{config[:pid_file]}"
        exit(1)
      end
      at_exit { File.unlink config[:pid_file] rescue nil }
    end

    # create a logger
    @logger = ResqueStarter::Logger.new(
      @config[:log_file], @config[:log_shift_age], @config[:log_shift_size]
    )
    @logger.level = @config[:log_level]

    # create guard that removes the status file
    if config[:status_file]
      at_exit { File.unlink config[:status_file] rescue nil }
    end
  end

  def start_resque
    @logger.info "starting resque starter (master) #{Process.pid}"
    maintain_worker_count

    install_signal_handler
    @handle_thr = start_handle_thread
    while true
      break unless @handle_thr.alive? # dies if @shutdown and @old_workers.empty?
      begin
        pid, status = Process.waitpid2(-1)
        @logger.info "resque worker #{pid} died, status:#{status.exitstatus}"
        @self_write.puts(pid)
      rescue Errno::ECHILD
        @handle_thr.kill if @shutdown # @old_workers should be empty
        sleep 0.1 # avoid busy loop for no child by TTOU
      end
    end

    @logger.info "shutting down resque starter (master) #{Process.pid}"
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

  def update_status_file
    return unless @config[:status_file]
    # pid => worker_nr
    status = {'old_workers' => @old_workers}.to_yaml
    File.write(@config[:status_file], status)
  end

  def handle_waitpid2(pid)
    @old_workers.delete(pid)
    update_status_file
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
      @logger.info msg << "immediately kill all resque workers then exit:#{pids}"
      @shutdown = true
      Process.kill(sig, *pids)
    when 'QUIT'
      @logger.info msg << "wait for all resque workers to finish processing then exit:#{pids}"
      @shutdown = true
      Process.kill(sig, *pids)
    when 'USR1'
      @logger.info msg << "immediately kill the child of all resque workers:#{pids}"
      Process.kill(sig, *pids)
    when 'USR2'
      @logger.info msg << "don't start to process any new jobs:#{pids}"
      Process.kill(sig, *pids)
    when 'CONT'
      @logger.info msg << "start to process new jobs again after USR2:#{pids}"
      Process.kill(sig, *pids)
    when 'TTIN'
      @num_workers += 1
      @logger.info msg << "increment the number of resque workers:#{@num_workers}"
      maintain_worker_count # ToDo: forking from a thread would be unsafe
    when 'TTOU'
      @num_workers -= 1 if @num_workers > 0
      @logger.info msg << "decrement the number of resque workers:#{@num_workers}"
      maintain_worker_count
    end
  rescue Errno::ESRCH
  rescue => e
    @logger.error(e)
    exit(1)
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
      config[:before_fork].call(self, worker, worker_nr)
      if pid = fork
        @old_workers[pid] = worker_nr
        update_status_file
        @logger.info "starting new resque worker #{pid}"
      else # child
        @self_read.close rescue nil
        @self_write.close rescue nil
        config[:after_fork].call(self, worker, worker_nr)
        worker.work(config[:dequeue_interval])
        exit
      end
    end
  rescue => e
    @logger.error(e)
    exit(1)
  end
end
