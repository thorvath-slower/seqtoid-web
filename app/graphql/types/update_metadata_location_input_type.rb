module Types
  # Federation mesh INPUT
  # `query_SampleMetadata_metadata_items_location_validated_value_oneOf_1_Input` (CZID-304):
  # the location-object branch of the UpdateMetadata value. Passed through to
  # Sample#metadatum_add_or_update as the metadata value (the federation forwarded the same
  # object). Mirrors the oneOf_1 output type's fields.
  class UpdateMetadataLocationInputType < Types::BaseInputObject
    graphql_name "query_SampleMetadata_metadata_items_location_validated_value_oneOf_1_Input"

    argument :id, String, required: false, camelize: false
    argument :name, String, required: false, camelize: false
    argument :geo_level, String, required: false, camelize: false
    argument :country_name, String, required: false, camelize: false
    argument :country_code, String, required: false, camelize: false
    argument :state_name, String, required: false, camelize: false
    argument :subdivision_name, String, required: false, camelize: false
    argument :city_name, String, required: false, camelize: false
    argument :osm_id, Int, required: false, camelize: false
    argument :locationiq_id, Types::JsonScalar, required: false, camelize: false
    argument :lat, Types::JsonScalar, required: false, camelize: false
    argument :lng, Types::JsonScalar, required: false, camelize: false
    argument :created_at, String, required: false, camelize: false
    argument :updated_at, String, required: false, camelize: false
    argument :osm_type, String, required: false, camelize: false
    argument :country_id, Int, required: false, camelize: false
    argument :state_id, Int, required: false, camelize: false
    argument :subdivision_id, Int, required: false, camelize: false
    argument :city_id, String, required: false, camelize: false
    argument :raw_value, String, required: false, camelize: false
    argument :title, String, required: false, camelize: false
    argument :description, String, required: false, camelize: false
    argument :key, String, required: false, camelize: false
    argument :refetch_adjusted_location, Boolean, required: false, camelize: false
  end
end
