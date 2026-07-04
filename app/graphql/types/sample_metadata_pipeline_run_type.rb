module Types
  # Federation mesh type `query_SampleMetadata_additional_info_pipeline_run` (CZID-285):
  # the curated pipeline-run display (PipelineRun#as_json with `version` replaced and
  # `host_subtracted` humanized). `id` is stringified to match the federation contract.
  # This is a distinct mesh type from the app's existing PipelineRunType -- it is NOT a
  # rename or replacement of that type (CZID-285 never-rename rule).
  class SampleMetadataPipelineRunType < Types::BaseObject
    graphql_name "query_SampleMetadata_additional_info_pipeline_run"

    field :id, String, null: true, camelize: false
    field :sample_id, Int, null: true, camelize: false
    field :created_at, String, null: true, camelize: false
    field :updated_at, String, null: true, camelize: false
    field :job_status, String, null: true, camelize: false
    field :finalized, Int, null: true, camelize: false
    field :total_reads, Int, null: true, camelize: false
    field :adjusted_remaining_reads, Int, null: true, camelize: false
    field :unmapped_reads, Int, null: true, camelize: false
    field :subsample, Int, null: true, camelize: false
    field :pipeline_branch, String, null: true, camelize: false
    field :total_ercc_reads, Int, null: true, camelize: false
    field :fraction_subsampled, Float, null: true, camelize: false
    field :pipeline_version, String, null: true, camelize: false
    field :pipeline_commit, String, null: true, camelize: false
    field :truncated, Types::JsonScalar, null: true, camelize: false
    field :results_finalized, Int, null: true, camelize: false
    field :alignment_config_id, Int, null: true, camelize: false
    field :alert_sent, Int, null: true, camelize: false
    field :dag_vars, Types::JsonScalar, null: true, camelize: false
    field :assembled, Int, null: true, camelize: false
    field :max_input_fragments, Int, null: true, camelize: false
    field :error_message, Types::JsonScalar, null: true, camelize: false
    field :known_user_error, Types::JsonScalar, null: true, camelize: false
    field :pipeline_execution_strategy, String, null: true, camelize: false
    field :sfn_execution_arn, String, null: true, camelize: false
    field :use_taxon_whitelist, Boolean, null: true, camelize: false
    field :wdl_version, String, null: true, camelize: false
    field :s3_output_prefix, String, null: true, camelize: false
    field :executed_at, String, null: true, camelize: false
    field :time_to_finalized, Int, null: true, camelize: false
    field :time_to_results_finalized, Int, null: true, camelize: false
    field :qc_percent, Float, null: true, camelize: false
    field :compression_ratio, Float, null: true, camelize: false
    field :deprecated, Boolean, null: true, camelize: false
    field :technology, String, null: true, camelize: false
    field :guppy_basecaller_setting, Types::JsonScalar, null: true, camelize: false
    field :total_bases, Types::JsonScalar, null: true, camelize: false
    field :unmapped_bases, Types::JsonScalar, null: true, camelize: false
    field :fraction_subsampled_bases, Types::JsonScalar, null: true, camelize: false
    field :truncated_bases, Types::JsonScalar, null: true, camelize: false
    field :deleted_at, Types::JsonScalar, null: true, camelize: false
    field :mapped_reads, Types::JsonScalar, null: true, camelize: false
    field :version, Types::SampleMetadataPipelineRunVersionType, null: true, camelize: false
    field :host_subtracted, String, null: true, camelize: false
  end
end
