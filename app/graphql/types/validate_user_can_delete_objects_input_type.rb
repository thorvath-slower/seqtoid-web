module Types
  class ValidateUserCanDeleteObjectsInputType < Types::BaseInputObject
    graphql_name "ValidateUserCanDeleteObjectsInput"

    # Nullable inner type ([Int]/[String], not [Int!]/[String!]) to match the
    # frontend query variables ($selectedIds: [Int], $selectedIdsStrings: [String]).
    argument :selected_ids, [Integer, { null: true }], required: false
    argument :selected_ids_strings, [String, { null: true }], required: false
    argument :workflow, String, required: true
    # Accepted for parity with the federation query; CSRF is not needed for the
    # in-process Rails GraphQL endpoint.
    argument :authenticity_token, String, required: false
  end
end
