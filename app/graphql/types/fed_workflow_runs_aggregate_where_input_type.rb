module Types
  # `where` filter for fedWorkflowRunsAggregate (CZID-285). collectionId._in restricts
  # the result to a paginated subset of project ids.
  class FedWorkflowRunsAggregateWhereInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_where_Input"

    argument :id, Types::StringListInFilterType, required: false, camelize: false
    argument :collectionId, Types::IntListInFilterType, required: false, camelize: false
    argument :workflowVersion, Types::FedWorkflowRunsAggregateWhereWorkflowVersionInputType, required: false, camelize: false
    argument :deprecatedById, Types::NullCheckFilterType, required: false, camelize: false
  end
end
