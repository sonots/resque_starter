require 'resque'
require "resque_starter/version"

class ResqueStarter
  attr_reader :opts

  def initialize(opts)
    @opts = opts
    @signals_received  = []
    @current_worker    = nil
    @old_workers       = {}
    @last_restart_time = []
    @mutex             = Mutex.new
    @worker_processes  = opts[:concurrency]
    @queues            = opts[:queues].split(',') if opts[:queues]
  end

  def start_resque
    $stderr.puts "starting resque_starter #{Process.pid}"
    @signal_thr = start_signal_thread
    preload if opts[:preload_app]
    maintain_worker_count

    while true
      break unless @signal_thr.alive?
      pid, status = Process.wait2
      $stderr.puts "worker #{pid} died, status:#{status.exitstatus}"
      @mutex.synchronize { @old_workers.delete(pid) }
      if @shutdown
        break if @old_workers.empty?
      else
        maintain_worker_count
      end
    end

    @signal_thr.kill
  end

  def start_signal_thread
    self_read, self_write = IO.pipe
    install_signal_handler(self_write)
    Thread.new { wait_and_handle_signal(self_read) }
  end

  def install_signal_handler(self_write)
    %w(TERM INT QUIT USR1 USR2 CONT TTIN TTOU).each do |sig|
      trap(sig) { self_write.puts(sig) }
    end
  end

  def wait_and_handle_signal(self_read)
    while readable_io = IO.select([self_read])
      signal = readable_io.first[0].gets.strip
      handle_signal(signal)
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
    pids = nil
    @mutex.synchronize do
      pids = @old_workers.keys.sort
    end
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
      $stderr.puts msg << "don't start tp process any new jobs:#{pids.join(',')}"
      Process.kill(sig, *pids)
    when 'CONT'
      $stderr.puts msg << "start to process new jobs again after USR2:#{pids.join(',')}"
      Process.kill(sig, *pids)
    when 'TTIN'
      @worker_processes += 1
      $stderr.puts msg << "increment the number of workers:#{@worker_processes}"
      maintain_worker_count # ToDo: forking from a thread would be unsafe
    when 'TTOU'
      @worker_processes -= 1 if @worker_processes > 0
      $stderr.puts msg << "decrement the number of workers:#{@worker_processes}"
      maintain_worker_count
    end
  rescue
    abort
  end

  def maintain_worker_count
    return if (off = @old_workers.size - @worker_processes) == 0
    return spawn_missing_workers if off < 0
    @old_workers.dup.each_pair {|pid, nr|
      if nr >= @worker_processes
        Process.kill(:QUIT, pid) rescue nil
      end
    }
  end

  def spawn_missing_workers
    worker_nr = -1
    until (worker_nr += 1) == @worker_processes
      @old_workers.value?(worker_nr) and next
      worker = Resque::Worker.new(*@queues)
      # before_fork.call(self, worker)
      if pid = fork
        @old_workers[pid] = worker_nr
        $stderr.puts "starting new worker #{pid}"
      else # child
        # after_fork_internal
        worker.work(opts[:dequeue_interval])
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
