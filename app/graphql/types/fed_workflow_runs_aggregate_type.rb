module Types
  # Federation mesh type `fedWorkflowRunsAggregate` (CZID-285, 303c): the DiscoveryView
  # per-project per-workflow run counts, mapped from ProjectsController#index sample_counts.
  class FedWorkflowRunsAggregateType < Types::BaseObject
    graphql_name "fedWorkflowRunsAggregate"

    field :aggregate, [Types::FedWorkflowRunsAggregateItemType], null: true, camelize: false
  end
end
