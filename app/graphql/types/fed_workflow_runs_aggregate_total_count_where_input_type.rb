module Types
  # `where` filter for fedWorkflowRunsAggregateTotalCount (CZID-285).
  class FedWorkflowRunsAggregateTotalCountWhereInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregateTotalCount_input_where_Input"

    argument :collectionId, Types::IntListInFilterType, required: false, camelize: false
    argument :deprecatedById, Types::NullCheckFilterType, required: false, camelize: false
    argument :workflowVersion, Types::FedWorkflowRunsAggregateTotalCountWhereWorkflowVersionInputType, required: false, camelize: false
  end
end
