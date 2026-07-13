module Types
  # Federation mesh type `query_fedConsensusGenomes_items_referenceGenome` (CZID-285).
  class FedConsensusGenomesReferenceGenomeType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_referenceGenome"

    field :file, Types::FedConsensusGenomesReferenceGenomeFileType, null: true, camelize: false
  end
end
