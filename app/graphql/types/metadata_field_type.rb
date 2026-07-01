module Types
  # Ported from the GraphQL federation server (CZID-285). One item of the
  # MetadataFields list -- mirrors MetadataField#field_info. Field method names
  # match the field_info hash keys exactly (some camelCase, some snake_case), and
  # camelize:false preserves the federation's field names for the Relay cutover.
  class MetadataFieldType < Types::BaseObject
    graphql_name "MetadataField"

    field :key, String, null: true
    field :dataType, String, null: true, camelize: false
    field :name, String, null: true
    field :options, [String], null: true
    field :group, String, null: true
    field :host_genome_ids, [Integer], null: true, camelize: false
    field :description, String, null: true
    field :is_required, Integer, null: true, camelize: false
    field :isBoolean, GraphQL::Types::Boolean, null: true, camelize: false
  end
end
