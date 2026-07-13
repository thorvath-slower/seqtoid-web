module Types
  # `where.entityInputs` filter for fedWorkflowRuns (CZID-285).
  class FedWorkflowRunsWhereEntityInputsInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_where_entityInputs_Input"

    argument :entityType, Types::StringEqFilterType, required: false, camelize: false
    argument :inputEntityId, Types::NullCheckFilterType, required: false, camelize: false
  end
end
