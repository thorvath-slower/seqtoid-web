module Types
  # Shared discovery filter leaf -- `{ _eq: String }`. CZID-285.
  class StringEqFilterType < Types::BaseInputObject
    graphql_name "StringEqFilter"

    argument :_eq, String, required: false, camelize: false
  end
end
