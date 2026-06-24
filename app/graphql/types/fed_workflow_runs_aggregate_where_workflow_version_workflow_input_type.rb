module Types
  # `where.workflowVersion.workflow` filter for fedWorkflowRunsAggregate (CZID-285).
  class FedWorkflowRunsAggregateWhereWorkflowVersionWorkflowInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_where_workflowVersion_workflow_Input"

    argument :name, Types::StringListInFilterType, required: false, camelize: false
  end
end
