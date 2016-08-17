#!/usr/bin/env ruby

require 'optparse'
require_relative '../lib/resque_starter'

opts = {
}
OptionParser.new do |opt|
  opt.on(
    '--config=config_file',
    'path to config file (requirement)',
  ) {|v| opts[:config_file] = v }
  opt.on(
    '--version',
    'print version',
  ) {|v| puts ResqueStarter::VERSION; exit 0 }
  
  opt.parse!(ARGV)
end

starter = ResqueStarter.new(opts[:config_file])
starter.start_resque
