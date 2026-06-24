module Types
  # `where.workflowVersion.workflow` filter for fedWorkflowRunsAggregateTotalCount
  # (CZID-285).
  class FedWorkflowRunsAggregateTotalCountWhereWorkflowVersionWorkflowInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregateTotalCount_input_where_workflowVersion_workflow_Input"

    argument :name, Types::StringListInFilterType, required: false, camelize: false
  end
end
