module Types
  # An `orderBy` item for fedConsensusGenomes (CZID-285). Modeled so the frontend input
  # validates; ordering is applied via todoRemove.orderBy/orderDir in the discovery
  # pipeline, mirroring the federation resolver.
  class FedConsensusGenomesOrderByItemInputType < Types::BaseInputObject
    graphql_name "queryInput_fedConsensusGenomes_input_orderBy_items_Input"

    argument :accession, Types::FedConsensusGenomesOrderByAccessionInputType, required: false, camelize: false
    argument :metrics, Types::FedConsensusGenomesOrderByMetricsInputType, required: false, camelize: false
  end
end
