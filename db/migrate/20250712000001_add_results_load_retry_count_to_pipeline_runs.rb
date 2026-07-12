# frozen_string_literal: true

# Tracks how many times we have auto-retried loading a pipeline run's results
# after the compute (SFN) succeeded but one or more outputs failed to load
# (e.g. a transient infra error). Bounds the cheap-retry auto-heal in
# PipelineRun#finalize_results so a healthy pipeline is not surfaced as a
# failed sample, without looping forever. See CZID-676 / #676.
class AddResultsLoadRetryCountToPipelineRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :pipeline_runs, :results_load_retry_count, :integer, default: 0, null: false
  end
end
