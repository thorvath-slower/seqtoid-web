module Types
  # Shared discovery filter leaf -- `{ _gte: String }`. CZID-285.
  class StringGteFilterType < Types::BaseInputObject
    graphql_name "StringGteFilter"

    argument :_gte, String, required: false, camelize: false
  end
end
