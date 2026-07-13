module Types
  # `orderByArray[].workflowVersion` for fedWorkflowRuns (CZID-285).
  class FedWorkflowRunsOrderByWorkflowVersionInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_orderByArray_items_workflowVersion_Input"

    argument :version, String, required: false, camelize: false
  end
end
