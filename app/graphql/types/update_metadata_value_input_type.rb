module Types
  # Federation mesh input `mutationInput_UpdateMetadata_input_value_Input` (CZID-304): the
  # @oneOf metadata value -- either a plain `String` or a location object. The frontend
  # supplies exactly one; the resolver prefers the String branch (matching the federation).
  # Modeled as a plain input (both nullable) rather than graphql-ruby `one_of` to avoid a
  # hard dependency on that feature.
  class UpdateMetadataValueInputType < Types::BaseInputObject
    graphql_name "mutationInput_UpdateMetadata_input_value_Input"

    argument :String, String, required: false, camelize: false, as: :string_value
    argument :query_SampleMetadata_metadata_items_location_validated_value_oneOf_1_Input,
             Types::UpdateMetadataLocationInputType,
             required: false,
             camelize: false,
             as: :location_value
  end
end
