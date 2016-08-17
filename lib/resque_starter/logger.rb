require 'resque_starter/version'
require 'logger'

class ResqueStarter::Logger < ::Logger
  class Formatter
    def call(severity, time, progname, msg)
      "#{time.iso8601} [#{severity}] #{format_message(msg)}\n"
    end

    def format_message(message)
      case message
      when ::Exception
        e = message
        "#{e.class} (#{e.message})\\n  #{e.backtrace.join("\\n  ")}"
      else
        message.to_s
      end
    end
  end

  def initialize(logdev, shift_age = 0, shift_size = 1048576)
    logdev = STDOUT if logdev == 'STDOUT'
    logdev = STDERR if logdev == 'STDERR'
    super(logdev, shift_age, shift_size)
    @formatter = Formatter.new
  end

  def level=(level)
    level = eval("::Logger::#{level.upcase}") if level.is_a?(String)
    super(level)
  end
end
