#!/usr/bin/ruby

require 'optparse'
require_relative '../lib/resque_starter'

opts = {
  :concurrency => 2,
  :preload_app => false,
  :queues => 'high,low',
  :dequeue_interval => 5, # seconds
  # log
  # pid_file
  # status_file
}
OptionParser.new do |opt|
  opt.on(
    '--concurrency=num',
    'Number of concurrency (number of processes) of the resque worker (default: 1)',
  ) {|v| opts[:concurrency] = v.to_i }
  opt.on(
    '--version',
    'print version',
  ) {|v| puts ResqueStarter::VERSION; exit 0 }
  
  opt.parse!(ARGV)
end

starter = ResqueStarter.new(opts)
starter.start_resque
