module Types
  # Federation mesh type `query_fedBulkDownloads_items_params_items` (CZID-285): a
  # sidebar param of the bulk download (download_format, metrics, etc.).
  class FedBulkDownloadsParamType < Types::BaseObject
    graphql_name "query_fedBulkDownloads_items_params_items"

    field :paramType, String, null: true, camelize: false
    field :displayName, String, null: true, camelize: false
    field :value, String, null: true, camelize: false
  end
end
