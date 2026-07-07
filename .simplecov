SimpleCov.start 'rails' do
  add_group "Services", "app/services"

  enable_coverage :branch

  # parallel_tests runs the suite across N processes; each writes a distinct result
  # (command_name is set per-process below) and SimpleCov merges them into one final
  # report so the coverage % matches a serial run (no double-count, no undercount).
  # merge_timeout is generous so a long parallel run's earliest result isn't dropped.
  use_merging true
  merge_timeout 3600

  # Please add tests for new code so that we don't fall below the minimums!
  # To view report after running tests locally, go to 'coverage/index.html'.
  #
  # If needed, you can exclude code by wrapping it in # :nocov:
  # # :nocov:
  # def skip_this_method
  #   never_reached
  # end
  # # :nocov:
  #
  # Line coverage measures % of lines executed.
  # Branch coverage measures % of conditional branches executed.
  minimum_coverage line: 61, branch: 46

  # Exclude mostly manual tasks for now:
  add_filter "/lib/tasks"
  add_filter "/lib/seed_resources"
  add_filter "db/seeds.rb"
end
