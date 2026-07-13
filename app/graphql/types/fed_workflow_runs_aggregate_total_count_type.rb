module Types
  # Federation mesh type `fedWorkflowRunsAggregateTotalCount` (CZID-285, 303c): the
  # DiscoveryView per-workflow total counts (domain-wide), mapped from
  # SamplesController#stats countByWorkflow.
  class FedWorkflowRunsAggregateTotalCountType < Types::BaseObject
    graphql_name "fedWorkflowRunsAggregateTotalCount"

    field :aggregate, [Types::FedWorkflowRunsAggregateTotalCountItemType], null: true, camelize: false
  end
end
