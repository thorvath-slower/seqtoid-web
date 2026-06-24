module Types
  class BulkDownloadCgOverviewInputType < Types::BaseInputObject
    graphql_name "BulkDownloadCGOverviewInput"

    argument :workflow_run_ids, [Integer, { null: true }], required: false
    argument :workflow_run_ids_strings, [String, { null: true }], required: false
    argument :include_metadata, GraphQL::Types::Boolean, required: true
    argument :download_type, String, required: true
    argument :workflow, String, required: true
    # Accepted for parity with the federation query; unused server-side.
    argument :authenticity_token, String, required: false
  end
end
