module Types
  # `orderBy[].metrics` for fedConsensusGenomes (CZID-285).
  class FedConsensusGenomesOrderByMetricsInputType < Types::BaseInputObject
    graphql_name "queryInput_fedConsensusGenomes_input_orderBy_items_metrics_Input"

    argument :coverageDepth, String, required: false, camelize: false
    argument :totalReads, String, required: false, camelize: false
    argument :gcPercent, String, required: false, camelize: false
    argument :refSnps, String, required: false, camelize: false
    argument :percentIdentity, String, required: false, camelize: false
    argument :nActg, String, required: false, camelize: false
    argument :percentGenomeCalled, String, required: false, camelize: false
    argument :nMissing, String, required: false, camelize: false
    argument :nAmbiguous, String, required: false, camelize: false
    argument :referenceGenomeLength, String, required: false, camelize: false
  end
end
