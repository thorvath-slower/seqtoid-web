module Types
  # An `orderByArray` item for fedWorkflowRuns (CZID-285). Ordering is applied via
  # todoRemove.orderBy/orderDir (mirroring the federation resolver); this is modeled
  # so the frontend's input validates.
  class FedWorkflowRunsOrderByArrayItemInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_orderByArray_items_Input"

    argument :startedAt, String, required: false, camelize: false
    argument :workflowVersion, Types::FedWorkflowRunsOrderByWorkflowVersionInputType, required: false, camelize: false
  end
end
