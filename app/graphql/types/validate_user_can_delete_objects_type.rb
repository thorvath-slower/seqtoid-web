module Types
  # Ported from the GraphQL federation server (CZID-285). Mirrors the federation's
  # CZIDREST `ValidateUserCanDeleteObjects` response shape.
  class ValidateUserCanDeleteObjectsType < Types::BaseObject
    graphql_name "ValidateUserCanDeleteObjects"

    field :valid_ids, [Integer], null: true
    field :valid_ids_strings, [String], null: true
    field :invalid_sample_names, [String], null: true
    field :error, String, null: true
  end
end
