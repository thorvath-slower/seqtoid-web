module Types
  # Federation mesh type `query_SampleMetadata_metadata_items` (CZID-285): one row of
  # `Sample#metadata_with_base_type`. `id` is stringified and `location_validated_value`
  # is resolved to the union by the resolver to match the federation contract.
  class SampleMetadataMetadataItemType < Types::BaseObject
    graphql_name "query_SampleMetadata_metadata_items"

    field :id, String, null: true, camelize: false
    field :key, String, null: true, camelize: false
    # `raw_value` shadows GraphQL::Schema::Object#raw_value, so graphql-ruby would
    # call that inherited method instead of reading the backing hash -- resolve it
    # explicitly off the object.
    field :raw_value, String, null: true, camelize: false, resolver_method: :resolve_raw_value
    field :string_validated_value, String, null: true, camelize: false
    field :number_validated_value, String, null: true, camelize: false
    field :sample_id, Int, null: true, camelize: false
    field :created_at, String, null: true, camelize: false
    field :updated_at, String, null: true, camelize: false
    field :date_validated_value, String, null: true, camelize: false
    field :location_validated_value,
          Types::SampleMetadataLocationValidatedValueUnion,
          null: true,
          camelize: false
    field :metadata_field_id, Int, null: true, camelize: false
    field :location_id, Int, null: true, camelize: false
    field :base_type, String, null: true, camelize: false

    def resolve_raw_value
      object[:raw_value]
    end
  end
end
