module Types
  # Federation mesh input `queryInput_fedWorkflowRuns_input_Input` (CZID-285). The
  # top-level name must match the mesh so the existing frontend query validates; nested
  # input types are local (the 305 cutover regenerates Relay artifacts from this schema).
  # The resolver consumes `todoRemove` (the discovery filter bag); `where`/`orderByArray`
  # are modeled so the frontend's input validates but are applied via todoRemove's
  # orderBy/orderDir, mirroring the federation resolver.
  class FedWorkflowRunsInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_Input"

    argument :todoRemove, Types::FedWorkflowRunsTodoRemoveInputType, required: false, camelize: false
    argument :where, Types::FedWorkflowRunsWhereInputType, required: false, camelize: false
    argument :orderByArray, [Types::FedWorkflowRunsOrderByArrayItemInputType], required: false, camelize: false
  end
end
