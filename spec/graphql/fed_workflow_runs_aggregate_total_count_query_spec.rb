require "rails_helper"

# CZID-285 (303c): native Rails GraphQL port of the federation
# fedWorkflowRunsAggregateTotalCount op. Reproduces SamplesController#stats
# countByWorkflow and shapes it into the aggregate/groupBy response.
RSpec.describe GraphqlController, type: :request do
  create_users

  FED_WR_AGG_TOTAL_QUERY = <<GQL
  query DiscoveryViewFCFedWorkflowsTotalCountQuery($input: queryInput_fedWorkflowRunsAggregateTotalCount_input_Input) {
    fedWorkflowRunsAggregateTotalCount(input: $input) {
      aggregate {
        count
        groupBy {
          workflowVersion {
            workflow {
              name
            }
          }
        }
      }
    }
  }
GQL

  def post_query(variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: FED_WR_AGG_TOTAL_QUERY,
      variables: variables,
    }.to_json
  end

  context "Joe" do
    before { sign_in @joe }

    it "returns per-workflow total counts grouped by workflow name" do
      project = create(:project, users: [@joe])
      mngs_sample = create(:sample, project: project, user: @joe,
                                    initial_workflow: WorkflowRun::WORKFLOW[:short_read_mngs])
      cg_sample = create(:sample, project: project, user: @joe,
                                  initial_workflow: WorkflowRun::WORKFLOW[:consensus_genome])
      create(:workflow_run, sample: cg_sample, user: @joe, workflow: WorkflowRun::WORKFLOW[:consensus_genome])
      create(:workflow_run, sample: cg_sample, user: @joe, workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      post_query(input: { todoRemove: { domain: "my_data" } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      aggregate = parsed.dig("data", "fedWorkflowRunsAggregateTotalCount", "aggregate")
      counts = aggregate.to_h { |a| [a.dig("groupBy", "workflowVersion", "workflow", "name"), a["count"]] }

      # one mngs sample (counted by initial_workflow), two CG workflow runs
      expect(counts["short-read-mngs"]).to eq(1)
      expect(counts["consensus-genome"]).to eq(2)
      expect(counts["amr"]).to eq(0)
      # all five workflow buckets present, in the federation's order
      expect(aggregate.map { |a| a.dig("groupBy", "workflowVersion", "workflow", "name") }).to eq(
        ["short-read-mngs", "long-read-mngs", "consensus-genome", "amr", "benchmark"]
      )
    end
  end
end
