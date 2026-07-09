require 'resque/server'
require 'resque/scheduler/server' # Enables 'Schedule' tab (/resque/schedule)

Resque.redis = Redis.new(url: REDISCLOUD_URL)

Dir[Rails.root.join('app', 'jobs', '*.rb')].sort.each { |file| require file }

RESQUE_SERVER = Resque::Server.new
# Hide verbose exception pages
RESQUE_SERVER.settings.show_exceptions = false

# #544: `Resque.schedule=` (resque-scheduler) writes the schedule into Redis, so it opens a
# Redis connection at boot. Skip it during `rails assets:precompile` (marked by the build-only
# ENV["ASSETS_PRECOMPILE"], set in the Dockerfile) where no Redis is running -- asset compilation
# never uses the schedule. The YAML is still loadable; only the boot-time Redis write is skipped.
# ENV["ASSETS_PRECOMPILE"] is never set at runtime, so deployed behavior is unchanged.
Resque.schedule = YAML.load_file('config/resque_schedule.yml') unless ENV["ASSETS_PRECOMPILE"]
