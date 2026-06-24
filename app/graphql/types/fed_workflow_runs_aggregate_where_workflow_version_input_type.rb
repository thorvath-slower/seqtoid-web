module Types
  # `where.workflowVersion` filter for fedWorkflowRunsAggregate (CZID-285).
  class FedWorkflowRunsAggregateWhereWorkflowVersionInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_where_workflowVersion_Input"

    argument :workflow, Types::FedWorkflowRunsAggregateWhereWorkflowVersionWorkflowInputType, required: false, camelize: false
  end
end
