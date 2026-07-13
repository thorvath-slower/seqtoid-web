module Types
  # Federation mesh type `query_fedConsensusGenomes_items_referenceGenome_file`
  # (CZID-285).
  class FedConsensusGenomesReferenceGenomeFileType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_referenceGenome_file"

    field :downloadLink, Types::FedConsensusGenomesReferenceGenomeFileDownloadLinkType, null: true, camelize: false
  end
end
