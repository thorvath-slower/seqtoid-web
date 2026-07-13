module Types
  # Federation mesh type `query_fedBulkDownloads_items_entityInputs_items` (CZID-285):
  # a sample input (workflow run or pipeline run) of the bulk download.
  class FedBulkDownloadsEntityInputType < Types::BaseObject
    graphql_name "query_fedBulkDownloads_items_entityInputs_items"

    field :id, String, null: true, camelize: false
    field :name, String, null: true, camelize: false
  end
end
