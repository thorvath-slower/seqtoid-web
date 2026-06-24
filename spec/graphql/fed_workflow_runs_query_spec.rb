require "rails_helper"

# CZID-285 (303b): native Rails GraphQL port of the federation fedWorkflowRuns op
# (discovery-view mode). Exercises the shared WorkflowRunsFetching pipeline (mode: basic)
# plus the federation resolver's mapping to the workflow-run discovery shape.
RSpec.describe GraphqlController, type: :request do
  create_users

  FED_WORKFLOW_RUNS_QUERY = <<GQL
  query DiscoveryViewFCWorkflowsQuery($input: queryInput_fedWorkflowRuns_input_Input) {
    fedWorkflowRuns(input: $input) {
      id
      startedAt
      status
      errorLabel
      rawInputsJson
      workflowVersion {
        version
        workflow {
          name
        }
      }
      entityInputs {
        edges {
          node {
            inputEntityId
            entityType
          }
        }
      }
    }
  }
GQL

  def post_query(variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: FED_WORKFLOW_RUNS_QUERY,
      variables: variables,
    }.to_json
  end

  context "Joe" do
    before { sign_in @joe }

    it "maps discovery-view consensus-genome workflow runs to the federation shape" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)
      wr = create(:workflow_run,
                  sample: sample,
                  user: @joe,
                  workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                  status: WorkflowRun::STATUS[:succeeded],
                  wdl_version: "3.4.1",
                  inputs_json: { creation_source: "CLI" }.to_json)

      post_query(input: { todoRemove: { domain: "my_data" } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      data = parsed.dig("data", "fedWorkflowRuns")
      expect(data.length).to eq(1)

      item = data.first
      expect(item["id"]).to eq(wr.id.to_s)
      expect(item["status"]).to eq("COMPLETE")
      expect(item["errorLabel"]).to be_nil
      expect(item["rawInputsJson"]).to eq(%({"creation_source": "CLI"}))
      expect(item["workflowVersion"]).to eq(
        "version" => "3.4.1",
        "workflow" => { "name" => "CLI" }
      )
      expect(item.dig("entityInputs", "edges")).to eq([
        { "node" => { "inputEntityId" => sample.id.to_s, "entityType" => "sequencing_read" } },
      ])
    end

    it "validates CG workflow run ids for the bulk-download modal (where.id._in)" do
      project = create(:project, users: [@joe])
      sample = create(:sample, project: project, user: @joe)
      valid_cg = create(:workflow_run, sample: sample, user: @joe,
                                       workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                                       status: WorkflowRun::STATUS[:succeeded], deprecated: false)
      deprecated_cg = create(:workflow_run, sample: sample, user: @joe,
                                            workflow: WorkflowRun::WORKFLOW[:consensus_genome],
                                            deprecated: true)
      non_cg = create(:workflow_run, sample: sample, user: @joe,
                                     workflow: WorkflowRun::WORKFLOW[:amr])

      bulk_query = <<GQL
      query BulkDownloadModalValidConsensusGenomeWorkflowRunsQuery($input: queryInput_fedWorkflowRuns_input_Input) {
        fedWorkflowRuns(input: $input) {
          id
          ownerUserId
          status
        }
      }
GQL
      post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
        query: bulk_query,
        variables: { input: { where: { id: { _in: [valid_cg.id.to_s, deprecated_cg.id.to_s, non_cg.id.to_s] } } } },
      }.to_json

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      data = parsed.dig("data", "fedWorkflowRuns")
      # only the viewable, non-deprecated consensus-genome run is valid
      expect(data).to eq([
        { "id" => valid_cg.id.to_s, "ownerUserId" => @joe.id, "status" => valid_cg.status },
      ])
    end
  end
end
