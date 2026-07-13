module Types
  # Shared discovery filter leaf -- `{ _in: [String], _eq: String }`. `_eq` selects the
  # single-CG-result mode; `_in` filters discovery. CZID-285.
  class StringInEqFilterType < Types::BaseInputObject
    graphql_name "StringInEqFilter"

    argument :_in, [String], required: false, camelize: false
    argument :_eq, String, required: false, camelize: false
  end
end
