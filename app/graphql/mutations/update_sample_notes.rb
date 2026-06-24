module Mutations
  # Ported from the federation server (resolver-functions/UpdateSampleNotes) as part of
  # CZID-304. Serves `UpdateSampleNotes` natively instead of proxying
  # POST /samples/:id/save_metadata { field: "sample_notes", value }. Mirrors
  # SamplesController#save_metadata via the shared SampleFieldSaving helper.
  class UpdateSampleNotes < Mutations::BaseMutation
    include Mutations::SampleFieldSaving

    graphql_name "UpdateSampleNotes"

    argument :sample_id, String, required: false
    argument :input, Types::UpdateSampleNotesInputType, required: false

    field :status, String, null: true
    field :message, String, null: true

    def resolve(input:, sample_id: nil)
      sample = context[:current_power].updatable_samples.find(sample_id.to_i)
      save_sample_field(sample, "sample_notes", input.value)
    end
  end
end
