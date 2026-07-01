module Types
  # Shared discovery filter leaf -- `{ _is_null: Boolean }`. CZID-285.
  class NullCheckFilterType < Types::BaseInputObject
    graphql_name "NullCheckFilter"

    argument :_is_null, Boolean, required: false, camelize: false
  end
end
