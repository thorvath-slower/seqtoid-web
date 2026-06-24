module Types
  # Federation mesh type `query_SampleMetadata_additional_info_pipeline_run_version`
  # (CZID-285): the {pipeline, alignment_db} version map that
  # PipelineOutputsHelper#curate_pipeline_run_display synthesizes.
  class SampleMetadataPipelineRunVersionType < Types::BaseObject
    graphql_name "query_SampleMetadata_additional_info_pipeline_run_version"

    field :pipeline, String, null: true, camelize: false
    field :alignment_db, String, null: true, camelize: false
  end
end
