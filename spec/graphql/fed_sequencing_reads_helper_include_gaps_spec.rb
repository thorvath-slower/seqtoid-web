require "rails_helper"

# Regression for #452 (the ported-resolver helper-include bug class; sibling of the
# #451 get_app_config gap). The fedSequencingReads `with_sample_info` resolver runs the
# shared WorkflowRunsFetching pipeline, which transitively calls SamplesHelper methods
# that a GraphQL resolver does NOT auto-resolve the way a controller would:
#
#   discovery_workflow_runs -> format_workflow_runs (WorkflowRunsFetching), which calls
#     - get_visibility_by_sample_id                     (SamplesHelper)
#     - sample_uploader                                 (SamplesHelper)
#     - get_result_status_description_for_errored_sample (SamplesHelper)
#
# QueryType closes these by `include SamplesHelper` / `include WorkflowRunsFetching`. If a
# future change dropped one of those includes (or a helper began calling a not-yet-included
# helper) this path would raise NoMethodError -> a user-facing 500 on the DiscoveryView.
#
# Unlike fed_sequencing_reads_query_spec.rb's full-tree example, this does NOT stub
# discovery_workflow_runs: it drives the REAL fetch/format chain against real records so
# the transitive helper-include closure is actually exercised. The ids-only example there
# only reaches format_workflow_runs' `mode: "basic"` branch; this locks the richer
# `with_sample_info` branch (the one that touches uploader/visibility/error-status).
RSpec.describe GraphqlController, type: :request do
  create_users

  FULL_TREE_QUERY = <<GQL.freeze
  query DiscoveryViewFCSequencingReadsQuery($input: queryInput_fedSequencingReads_input_Input) {
    fedSequencingReads(input: $input) {
      id
      sample {
        railsSampleId
        name
        uploadError
        ownerUserId
        ownerUserName
        collection {
          public
        }
        metadatas {
          edges {
            node {
              fieldName
              value
            }
          }
        }
      }
    }
  }
GQL

  def post_query(query, variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: query,
      variables: variables,
    }.to_json
  end

  context "as Joe, exercising the real with_sample_info discovery chain (no stub)" do
    before { sign_in @joe }

    it "runs discovery_workflow_runs -> format_workflow_runs' SamplesHelper calls without NoMethodError" do
      project = create(:project, users: [@joe], public_access: 0)
      sample = create(
        :sample,
        project: project,
        user: @joe,
        name: "Discovery Sample",
        host_genome_name: "Human",
        metadata_fields: { "host_age" => "42" }
      )
      create(:workflow_run, sample: sample, user: @joe,
                            workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                            status: WorkflowRun::STATUS[:succeeded], deprecated: false)

      post_query(FULL_TREE_QUERY, input: { todoRemove: { domain: "my_data", workflow: "consensus-genome" } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)

      # The whole point: the transitive SamplesHelper calls must resolve. A missing include
      # would surface here as `undefined method 'sample_uploader'`
      # / `get_visibility_by_sample_id` / `get_result_status_description_for_errored_sample`.
      expect(error_messages(parsed)).not_to match(/undefined method/)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      read = parsed.dig("data", "fedSequencingReads")&.first
      expect(read).not_to be_nil
      expect(read.dig("sample", "railsSampleId")).to eq(sample.id)
      expect(read.dig("sample", "name")).to eq("Discovery Sample")
      # sample_uploader resolved -> owner fields populated for the run's owner.
      expect(read.dig("sample", "ownerUserId")).to eq(@joe.id)
      # get_visibility_by_sample_id resolved -> JS-Boolean coercion of a private project.
      expect(read.dig("sample", "collection", "public")).to be(false)
      # host_age survives getMetadataEdges (not one of the promoted fields).
      expect(read.dig("sample", "metadatas", "edges")).to include(
        "node" => { "fieldName" => "host_age", "value" => "42" }
      )
    end
  end

  def error_messages(parsed)
    Array(parsed["errors"]).map { |e| e["message"] }.join(" | ")
  end
end
