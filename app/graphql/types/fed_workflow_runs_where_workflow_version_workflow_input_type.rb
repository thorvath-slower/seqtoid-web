module Types
  # `where.workflowVersion.workflow` filter for fedWorkflowRuns (CZID-285).
  class FedWorkflowRunsWhereWorkflowVersionWorkflowInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_where_workflowVersion_workflow_Input"

    argument :name, Types::StringListInFilterType, required: false, camelize: false
  end
end
