module Types
  # Federation mesh input `queryInput_fedConsensusGenomes_input_Input` (CZID-285). Top
  # name matches the mesh so the frontend query validates; nested inputs are local.
  class FedConsensusGenomesInputType < Types::BaseInputObject
    graphql_name "queryInput_fedConsensusGenomes_input_Input"

    argument :limit, Int, required: false, camelize: false
    argument :offset, Int, required: false, camelize: false
    argument :where, Types::FedConsensusGenomesWhereInputType, required: false, camelize: false
    argument :orderBy, [Types::FedConsensusGenomesOrderByItemInputType], required: false, camelize: false
    argument :todoRemove, Types::FedConsensusGenomesTodoRemoveInputType, required: false, camelize: false
  end
end
