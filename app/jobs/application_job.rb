# These are necessary for the shared job mixins to be loaded before they are
# referenced at class-body eval time in /jobs/*. config/initializers/resque.rb
# explicitly requires each app/jobs/*.rb file at initializer time, before Zeitwerk
# autoloading is active, so any app/lib constant a job extends must be pre-required
# here (application_job.rb sorts first in that require loop).
require "instrumented_job"
require "resque_retry_with_dead_letter"

class ApplicationJob < ActiveJob::Base
end
