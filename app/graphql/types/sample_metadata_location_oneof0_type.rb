module Types
  # Federation mesh type
  # `query_SampleMetadata_metadata_items_location_validated_value_oneOf_0` (CZID-285):
  # the free-text branch of the location_validated_value union -- just the raw string
  # value surfaced as `name`.
  class SampleMetadataLocationOneof0Type < Types::BaseObject
    graphql_name "query_SampleMetadata_metadata_items_location_validated_value_oneOf_0"

    field :name, String, null: true, camelize: false
  end
end
