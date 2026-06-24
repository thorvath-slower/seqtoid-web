module Types
  # Federation mesh type
  # `query_fedConsensusGenomes_items_referenceGenome_file_downloadLink` (CZID-285): the
  # ref_fasta presigned download URL (mirrors WorkflowRunsController#cg_report_downloads).
  class FedConsensusGenomesReferenceGenomeFileDownloadLinkType < Types::BaseObject
    graphql_name "query_fedConsensusGenomes_items_referenceGenome_file_downloadLink"

    field :url, String, null: true, camelize: false
  end
end
