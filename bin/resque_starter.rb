#!/usr/bin/env ruby

require 'optparse'
require_relative '../lib/resque_starter'

opts = {
}
OptionParser.new do |opt|
  opt.on(
    '--config=file',
    'path to config file',
  ) {|v| opts[:config_file] = v }
  opt.on(
    '--version',
    'print version',
  ) {|v| puts ResqueStarter::VERSION; exit 0 }
  
  opt.parse!(ARGV)

  define_method(:usage) do |msg = nil|
    puts opt.to_s
    puts "error: #{msg}" if msg
    exit 1
  end
end

if opts[:config_file].nil?
  usage 'Option --config is required'
end

starter = ResqueStarter.new(opts[:config_file])
starter.start_resque
