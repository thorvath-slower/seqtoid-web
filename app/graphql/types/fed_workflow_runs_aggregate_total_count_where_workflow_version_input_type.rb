module Types
  # `where.workflowVersion` filter for fedWorkflowRunsAggregateTotalCount (CZID-285).
  class FedWorkflowRunsAggregateTotalCountWhereWorkflowVersionInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregateTotalCount_input_where_workflowVersion_Input"

    argument :workflow, Types::FedWorkflowRunsAggregateTotalCountWhereWorkflowVersionWorkflowInputType, required: false, camelize: false
  end
end
