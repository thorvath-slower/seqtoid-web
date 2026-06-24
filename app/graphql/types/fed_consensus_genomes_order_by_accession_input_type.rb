module Types
  # `orderBy[].accession` for fedConsensusGenomes (CZID-285).
  class FedConsensusGenomesOrderByAccessionInputType < Types::BaseInputObject
    graphql_name "queryInput_fedConsensusGenomes_input_orderBy_items_accession_Input"

    argument :accessionId, String, required: false, camelize: false
  end
end
