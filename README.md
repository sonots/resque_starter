# resque_starter

`resque_starter` is a tool to start and manage multiple resque workers concurrently.

# Purpose

[resque](https://github.com/resque/resque) provides [resque:workers](https://github.com/resque/resque#running-multiple-workers) task to run multiple resque workers, but it is only for development purpose as [code comments](https://github.com/resque/resque/blob/c295da9de0034b20ce79600e9f54fb279695f522/lib/resque/tasks.rb#L23-L38) says.
It also provides an example configuration of [god](http://godrb.com/) as [resque.god](https://github.com/resque/resque/blob/c295da9de0034b20ce79600e9f54fb279695f522/examples/god/resque.god), but it does not allow us to share memory of preloaded application with Copy-on-write (CoW).

This tool delicately manages multiple resque workers.

# Installation

Add this line to your application's Gemfile:

```ruby
gem 'resque_starter'
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install resque_starter
```

# Configuration

Please see [example/resque.conf.rb](./example/resque.conf.rb)

You can configure logger, pid file, number of concurrency, dequeue interval, queue lists.

# Usage

```
bundle exec resque_starter -c /path/to/resque.conf.rb
```

# Signals

Resque starter responds to a few different signals:

* TERM / INT - Quick shutdown, kills all workers immediately then exit
* QUIT - Graceful shutdown, waits for workers to finish processing then exit
* USR1 - Send USR1 to all workers, which immediately kill worker's child but don't exit
* USR2 - Send USR2 to all workers, which don't start to process any new jobs
* CONT - Send CONT to all workers, which start to process new jobs again after a USR2
* TTIN - Increment the number of worker processes by one
* TTOU - Decrement the number of worker processes by one with QUIT

# Graceful restart

Resque starter itself does not support graceful restart, yet. But, graceful restart can be done with [server-starter](https://github.com/sonots/ruby-server-starter).

Example configuration is available at [server-starter/example/resque](https://github.com/sonots/ruby-server-starter/blob/master/example/resque). See `start_server` and `config/resque.conf.rb` files.

**HOW IT WORKS**

On receiving HUP signal, server starter creates a new `resque_starter` (master) process.
The new `resque_starter` process forks a new resque worker.
On `after_fork`, the new `resque_starter` sends `TTOU` to old `resque_starter` process, and gracefully shutdowns an old resque worker.
By repeating this procedure, new `resque_starter` process can be gracefully restarted with suppressing number of concurrency up to `concurrency + 1`. 

# Contributing

1. Fork it ( https://github.com/sonots/resque_starter/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
