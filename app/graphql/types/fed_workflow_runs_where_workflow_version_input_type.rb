module Types
  # `where.workflowVersion` filter for fedWorkflowRuns (CZID-285).
  class FedWorkflowRunsWhereWorkflowVersionInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_where_workflowVersion_Input"

    argument :workflow, Types::FedWorkflowRunsWhereWorkflowVersionWorkflowInputType, required: false, camelize: false
  end
end
