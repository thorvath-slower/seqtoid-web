module Mutations
  # Ported from the federation server (resolver-functions/CreateBulkDownload) as part of
  # CZID-304. Serves `CreateBulkDownload` natively (POST /bulk_downloads), returning the
  # created bulk download as JSON -- the same payload BulkDownloadsController#create renders.
  #
  # NOTE: this op is frontend-UNUSED (the React app creates bulk downloads via the REST
  # `createBulkDownload` API helper, not this GraphQL mutation). Ported for schema
  # completeness; createAsyncBulkDownload is the one the frontend uses.
  class CreateBulkDownload < Mutations::BaseMutation
    include Mutations::BulkDownloadCreating

    graphql_name "CreateBulkDownload"

    argument :input, Types::CreateBulkDownloadInputType, required: false

    type Types::JsonScalar, null: true

    def resolve(input:)
      create_bulk_download(input).as_json
    end
  end
end
