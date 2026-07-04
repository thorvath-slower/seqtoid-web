module Types
  # `where` filter for fedWorkflowRuns (CZID-285). Modeled so the frontend's input
  # validates; the federation resolver did not translate these into the REST call
  # (it only forwarded todoRemove), so the resolver likewise does not apply them.
  class FedWorkflowRunsWhereInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_where_Input"

    # where.id._in drives the CG bulk-download-modal mode; modeled so that input
    # validates, but the resolver raises (that mode is a separate follow-up -- see
    # FedWorkflowRunsQuery).
    argument :id, Types::StringListInFilterType, required: false, camelize: false
    argument :deprecatedById, Types::NullCheckFilterType, required: false, camelize: false
    argument :collectionId, Types::IntListInFilterType, required: false, camelize: false
    argument :startedAt, Types::StringGteFilterType, required: false, camelize: false
    argument :entityInputs, Types::FedWorkflowRunsWhereEntityInputsInputType, required: false, camelize: false
    argument :workflowVersion, Types::FedWorkflowRunsWhereWorkflowVersionInputType, required: false, camelize: false
  end
end
