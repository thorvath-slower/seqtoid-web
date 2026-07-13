require "rails_helper"

# CZID-304: native Rails GraphQL ports of the federation UpdateSampleName /
# UpdateSampleNotes mutations. Mirror SamplesController#save_metadata via the shared
# SampleFieldSaving helper ({status, message}; blank-over-blank is ignored).
RSpec.describe GraphqlController, type: :request do
  create_users

  UPDATE_NAME_MUTATION = <<GQL
  mutation SampleDetailsModeUpdateSampleNameMutation($sampleId: String!, $input: mutationInput_UpdateSampleNotes_input_Input!) {
    UpdateSampleName(sampleId: $sampleId, input: $input) {
      status
      message
    }
  }
GQL

  UPDATE_NOTES_MUTATION = <<GQL
  mutation SampleDetailsModeUpdateSampleNotesMutation($sampleId: String!, $input: mutationInput_UpdateSampleNotes_input_Input!) {
    UpdateSampleNotes(sampleId: $sampleId, input: $input) {
      status
      message
    }
  }
GQL

  def post_mutation(query, variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: query,
      variables: variables,
    }.to_json
  end

  context "Joe" do
    before { sign_in @joe }

    it "UpdateSampleName updates the sample name" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe, name: "Old Name")

      post_mutation(UPDATE_NAME_MUTATION, { sampleId: sample.id.to_s, input: { value: "New Name", authenticityToken: "t" } })

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      expect(parsed.dig("data", "UpdateSampleName")).to eq("status" => "success", "message" => "Saved successfully")
      expect(sample.reload.name).to eq("New Name")
    end

    it "UpdateSampleNotes updates the sample notes" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)

      post_mutation(UPDATE_NOTES_MUTATION, { sampleId: sample.id.to_s, input: { value: "A note", authenticityToken: "t" } })

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      expect(parsed.dig("data", "UpdateSampleNotes")).to eq("status" => "success", "message" => "Saved successfully")
      expect(sample.reload.sample_notes).to eq("A note")
    end

    it "ignores a blank-over-blank notes write" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)

      post_mutation(UPDATE_NOTES_MUTATION, { sampleId: sample.id.to_s, input: { value: "   ", authenticityToken: "t" } })

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")
      expect(parsed.dig("data", "UpdateSampleNotes", "status")).to eq("ignored")
    end
  end
end
