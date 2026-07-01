module Types
  # Federation mesh type
  # `query_SampleMetadata_metadata_items_location_validated_value_oneOf_1` (CZID-285):
  # the resolved-Location branch of the location_validated_value union -- the full
  # Location record (its `id` is stringified to match the federation contract).
  class SampleMetadataLocationOneof1Type < Types::BaseObject
    graphql_name "query_SampleMetadata_metadata_items_location_validated_value_oneOf_1"

    field :id, String, null: true, camelize: false
    field :name, String, null: true, camelize: false
    field :geo_level, String, null: true, camelize: false
    field :country_name, String, null: true, camelize: false
    field :country_code, String, null: true, camelize: false
    field :state_name, String, null: true, camelize: false
    field :subdivision_name, String, null: true, camelize: false
    field :city_name, String, null: true, camelize: false
    field :osm_id, Int, null: true, camelize: false
    field :locationiq_id, Types::JsonScalar, null: true, camelize: false
    field :lat, Types::JsonScalar, null: true, camelize: false
    field :lng, Types::JsonScalar, null: true, camelize: false
    field :created_at, String, null: true, camelize: false
    field :updated_at, String, null: true, camelize: false
    field :osm_type, String, null: true, camelize: false
    field :country_id, Int, null: true, camelize: false
    field :state_id, Int, null: true, camelize: false
    field :subdivision_id, Int, null: true, camelize: false
    field :city_id, String, null: true, camelize: false
    # `raw_value` shadows GraphQL::Schema::Object#raw_value -- resolve it off the
    # backing hash so graphql-ruby doesn't call the inherited method.
    field :raw_value, String, null: true, camelize: false, resolver_method: :resolve_raw_value
    field :title, String, null: true, camelize: false
    field :description, String, null: true, camelize: false
    field :key, String, null: true, camelize: false
    field :refetch_adjusted_location, Boolean, null: true, camelize: false

    def resolve_raw_value
      object[:raw_value]
    end
  end
end
