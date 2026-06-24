module Types
  # Ported from the federation mesh input `queryInput_SampleMetadata_input_Input`
  # (CZID-285). Carries the optional pipelineVersion used to select a specific
  # pipeline run for the metadata sidebar.
  class SampleMetadataInputType < Types::BaseInputObject
    graphql_name "queryInput_SampleMetadata_input_Input"

    argument :pipeline_version, String, required: false, camelize: true
  end
end
