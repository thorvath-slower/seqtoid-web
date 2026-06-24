module Types
  # The filter bag for fedWorkflowRunsAggregateTotalCount (CZID-285). Only domain +
  # projectId are forwarded to the sample-stats count, mirroring the federation resolver.
  class FedWorkflowRunsAggregateTotalCountTodoRemoveInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregateTotalCount_input_todoRemove_Input"

    argument :domain, String, required: false
    argument :project_id, String, required: false
  end
end
