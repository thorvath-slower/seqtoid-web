module Types
  class MetadataFieldsInputType < Types::BaseInputObject
    graphql_name "MetadataFieldsInput"

    # [String]! — non-null list, nullable inner — to match the federation input.
    argument :sample_ids, [String, { null: true }], required: true
    # Accepted for parity with the federation query; unused server-side.
    argument :authenticity_token, String, required: false
  end
end
