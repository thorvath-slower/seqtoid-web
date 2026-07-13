module Mutations
  # Ported from the federation server (resolver-functions/createAsyncBulkDownloads) as part
  # of CZID-304. Serves `createAsyncBulkDownload` natively instead of proxying
  # POST /bulk_downloads. Creates + kicks off the bulk download via the shared
  # BulkDownloadCreating helper and returns just the new id (raising on error, matching the
  # federation's throw-on-error).
  class CreateAsyncBulkDownload < Mutations::BaseMutation
    include Mutations::BulkDownloadCreating

    graphql_name "createAsyncBulkDownload"

    argument :input, Types::CreateBulkDownloadInputType, required: false

    type Types::FedCreateBulkDownloadType, null: true

    def resolve(input:)
      bulk_download = create_bulk_download(input)
      { id: bulk_download.id.to_s }
    end
  end
end
