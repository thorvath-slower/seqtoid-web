module Types
  # Federation mesh type `query_fedBulkDownloads_items` (CZID-285, 303c): one row of the
  # bulk-download list, mapped from BulkDownloadsHelper#format_bulk_download. fileFormat
  # exists in the mesh contract but the federation never populated it (resolves nil).
  class FedBulkDownloadsType < Types::BaseObject
    graphql_name "query_fedBulkDownloads_items"

    field :id, String, null: true, camelize: false
    field :status, String, null: true, camelize: false
    field :startedAt, String, null: true, camelize: false
    field :downloadType, String, null: true, camelize: false
    field :fileFormat, String, null: true, camelize: false
    field :ownerUserId, Int, null: true, camelize: false
    field :fileSize, Float, null: true, camelize: false
    field :url, String, null: true, camelize: false
    field :analysisCount, Int, null: true, camelize: false
    field :errorMessage, String, null: true, camelize: false
    field :entityInputFileType, String, null: true, camelize: false
    field :entityInputs, [Types::FedBulkDownloadsEntityInputType], null: true, camelize: false
    field :params, [Types::FedBulkDownloadsParamType], null: true, camelize: false
    field :logUrl, String, null: true, camelize: false
  end
end
