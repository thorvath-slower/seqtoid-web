module Types
  # Federation mesh input `queryInput_fedWorkflowRunsAggregate_input_Input` (CZID-285).
  # The resolver consumes todoRemove (discovery filters) + where.collectionId._in (the
  # paginated project filter); the rest of where is modeled so the frontend validates.
  class FedWorkflowRunsAggregateInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_Input"

    argument :where, Types::FedWorkflowRunsAggregateWhereInputType, required: false, camelize: false
    argument :todoRemove, Types::FedWorkflowRunsAggregateTodoRemoveInputType, required: false, camelize: false
  end
end
