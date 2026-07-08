require 'resque/tasks'
require 'resque/scheduler/tasks'
require 'resque-scheduler'

task 'resque:setup' => :environment do
  ENV['QUEUE'] ||= '*'
  Resque.before_fork = proc { ActiveRecord::Base.establish_connection }
  # after_fork runs in the freshly forked child, right before it performs the job.
  # Verify (and transparently reconnect) the DB connection here so a worker whose
  # pooled connection was dropped by MySQL while idle self-heals instead of dying on
  # the classic "server has gone away" (#496).
  Resque.after_fork = proc { DbConnection.verify! }
end
