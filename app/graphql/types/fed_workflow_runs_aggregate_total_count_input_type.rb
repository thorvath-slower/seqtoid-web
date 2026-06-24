module Types
  # Federation mesh input `queryInput_fedWorkflowRunsAggregateTotalCount_input_Input`
  # (CZID-285). The resolver consumes todoRemove (domain/projectId); where is modeled so
  # the frontend input validates (the federation forwarded only domain+projectId).
  class FedWorkflowRunsAggregateTotalCountInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregateTotalCount_input_Input"

    argument :where, Types::FedWorkflowRunsAggregateTotalCountWhereInputType, required: false, camelize: false
    argument :todoRemove, Types::FedWorkflowRunsAggregateTotalCountTodoRemoveInputType, required: false, camelize: false
  end
end
