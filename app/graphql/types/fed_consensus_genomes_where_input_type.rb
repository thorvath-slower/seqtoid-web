module Types
  # `where` filter for fedConsensusGenomes (CZID-285). producingRunId._eq drives the
  # single-CG-result mode.
  class FedConsensusGenomesWhereInputType < Types::BaseInputObject
    graphql_name "queryInput_fedConsensusGenomes_input_where_Input"

    argument :collectionId, Types::IntListInFilterType, required: false, camelize: false
    argument :producingRunId, Types::StringInEqFilterType, required: false, camelize: false
  end
end
