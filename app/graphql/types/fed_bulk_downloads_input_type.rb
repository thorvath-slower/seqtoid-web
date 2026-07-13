module Types
  # Federation mesh input `queryInput_fedBulkDownloads_input_Input` (CZID-285).
  # searchBy/limit are admin-only narrowing (mirrors BulkDownloadsController#index).
  class FedBulkDownloadsInputType < Types::BaseInputObject
    graphql_name "queryInput_fedBulkDownloads_input_Input"

    argument :search_by, String, required: false
    argument :limit, Int, required: false, camelize: false
  end
end
