require "rails_helper"

# CZID-285 (303c): native Rails GraphQL port of the federation fedWorkflowRunsAggregate
# op. Reuses the shared ProjectsDiscovery pipeline (the same code /projects.json runs) for
# byte-identical per-project sample_counts, then emits the aggregate/groupBy entries.
RSpec.describe GraphqlController, type: :request do
  create_users

  FED_WR_AGGREGATE_QUERY = <<GQL
  query DiscoveryViewFCFedWorkflowRunsAggregateQuery($input: queryInput_fedWorkflowRunsAggregate_input_Input) {
    fedWorkflowRunsAggregate(input: $input) {
      aggregate {
        groupBy {
          collectionId
          workflowVersion {
            workflow {
              name
            }
          }
        }
        count
      }
    }
  }
GQL

  def post_query(variables)
    post "/graphql", headers: { "Content-Type" => "application/json" }, params: {
      query: FED_WR_AGGREGATE_QUERY,
      variables: variables,
    }.to_json
  end

  def entries_for(aggregate, collection_id)
    aggregate.select { |a| a.dig("groupBy", "collectionId") == collection_id }
             .to_h { |a| [a.dig("groupBy", "workflowVersion", "workflow", "name"), a["count"]] }
  end

  context "Joe" do
    before { sign_in @joe }

    it "emits per-project per-workflow counts from the project sample_counts" do
      project = create(:project, users: [@joe])
      create(:sample, project: project, user: @joe, initial_workflow: WorkflowRun::WORKFLOW[:short_read_mngs])
      create(:sample, project: project, user: @joe, initial_workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      post_query(input: { todoRemove: { domain: "my_data" } })

      expect(response).to have_http_status(:success)
      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      aggregate = parsed.dig("data", "fedWorkflowRunsAggregate", "aggregate")
      counts = entries_for(aggregate, project.id)

      expect(counts).to eq(
        "consensus-genome" => 1,
        "short-read-mngs" => 1,
        "amr" => 0
      )
      # 3 entries per project, in the federation's order
      project_entries = aggregate.select { |a| a.dig("groupBy", "collectionId") == project.id }
      expect(project_entries.map { |a| a.dig("groupBy", "workflowVersion", "workflow", "name") }).to eq(
        ["consensus-genome", "short-read-mngs", "amr"]
      )
    end

    it "restricts to where.collectionId._in" do
      project_a = create(:project, users: [@joe])
      project_b = create(:project, users: [@joe])
      create(:sample, project: project_a, user: @joe, initial_workflow: WorkflowRun::WORKFLOW[:consensus_genome])
      create(:sample, project: project_b, user: @joe, initial_workflow: WorkflowRun::WORKFLOW[:consensus_genome])

      post_query(input: { where: { collectionId: { _in: [project_a.id] } }, todoRemove: { domain: "my_data" } })

      parsed = JSON.parse(response.body)
      expect(parsed["errors"]).to(be_nil, "GraphQL errors: #{parsed['errors']}")

      aggregate = parsed.dig("data", "fedWorkflowRunsAggregate", "aggregate")
      collection_ids = aggregate.map { |a| a.dig("groupBy", "collectionId") }.uniq
      expect(collection_ids).to eq([project_a.id])
    end
  end
end
