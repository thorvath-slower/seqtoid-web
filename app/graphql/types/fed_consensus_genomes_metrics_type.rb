module Types
  # Federation mesh type `query_fedConsensusGenomes_items_metrics` (CZID-285): the CG
  # report metrics assembled from the run's coverage_viz + quality_metrics.
  class FedConsensusGenomesMetricsType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_metrics"

    field :coverageDepth, Float, null: true, camelize: false
    field :coverageBreadth, Float, null: true, camelize: false
    field :coverageTotalLength, Float, null: true, camelize: false
    field :coverageViz, [[Float, { null: true }], { null: true }], null: true, camelize: false
    field :coverageBinSize, Float, null: true, camelize: false
    field :totalReads, Int, null: true, camelize: false
    field :gcPercent, Float, null: true, camelize: false
    field :refSnps, Int, null: true, camelize: false
    field :percentIdentity, Float, null: true, camelize: false
    field :nActg, Int, null: true, camelize: false
    field :percentGenomeCalled, Float, null: true, camelize: false
    field :nMissing, Int, null: true, camelize: false
    field :nAmbiguous, Int, null: true, camelize: false
    field :referenceGenomeLength, Float, null: true, camelize: false
    field :mappedReads, Int, null: true, camelize: false
  end
end
