module Mutations
  # Ported from the federation server (resolver-functions/UpdateSampleName) as part of
  # CZID-304. Serves `UpdateSampleName` natively instead of proxying
  # POST /samples/:id/save_metadata { field: "name", value }. Mirrors
  # SamplesController#save_metadata via the shared SampleFieldSaving helper.
  class UpdateSampleName < Mutations::BaseMutation
    include Mutations::SampleFieldSaving

    graphql_name "UpdateSampleName"

    argument :sample_id, String, required: false
    argument :input, Types::UpdateSampleNotesInputType, required: false

    field :status, String, null: true
    field :message, String, null: true

    def resolve(input:, sample_id: nil)
      sample = context[:current_power].updatable_samples.find(sample_id.to_i)
      save_sample_field(sample, "name", input.value)
    end
  end
end
