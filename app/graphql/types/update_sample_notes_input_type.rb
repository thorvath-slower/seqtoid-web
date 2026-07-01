module Types
  # Federation mesh input `mutationInput_UpdateSampleNotes_input_Input` (CZID-304),
  # shared by the UpdateSampleName and UpdateSampleNotes mutations. authenticityToken is
  # accepted for input parity but unused (CSRF is moot in-process -- GraphqlController
  # uses a null session).
  class UpdateSampleNotesInputType < Types::BaseInputObject
    graphql_name "mutationInput_UpdateSampleNotes_input_Input"

    argument :value, String, required: true, camelize: false
    argument :authenticity_token, String, required: false
  end
end
