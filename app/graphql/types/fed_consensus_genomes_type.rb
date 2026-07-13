module Types
  # Federation mesh type `query_fedConsensusGenomes_items` (CZID-285, 303b). Two shapes:
  # the single-result CG report (metrics/accession/taxon/referenceGenome) and the thin
  # discovery row (sequencingRead.id only).
  class FedConsensusGenomesType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items"

    field :producingRunId, String, null: true, camelize: false
    field :taxon, Types::FedConsensusGenomesTaxonType, null: true, camelize: false
    field :accession, Types::FedConsensusGenomesAccessionType, null: true, camelize: false
    field :metrics, Types::FedConsensusGenomesMetricsType, null: true, camelize: false
    field :sequencingRead, Types::FedConsensusGenomesSequencingReadType, null: true, camelize: false
    field :referenceGenome, Types::FedConsensusGenomesReferenceGenomeType, null: true, camelize: false
  end
end
