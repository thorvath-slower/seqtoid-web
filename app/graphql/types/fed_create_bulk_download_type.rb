module Types
  # Federation mesh type `fedCreateBulkDownload` (CZID-304): the createAsyncBulkDownload
  # return -- just the new bulk download's id.
  class FedCreateBulkDownloadType < Types::BaseObject
    graphql_name "fedCreateBulkDownload"

    field :id, String, null: true, camelize: false
  end
end
