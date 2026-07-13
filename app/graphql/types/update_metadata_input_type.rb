module Types
  # Federation mesh input `mutationInput_UpdateMetadata_input_Input` (CZID-304).
  # authenticityToken is accepted for parity but unused (CSRF is moot in-process).
  class UpdateMetadataInputType < Types::BaseInputObject
    graphql_name "mutationInput_UpdateMetadata_input_Input"

    argument :field, String, required: true, camelize: false
    argument :value, Types::UpdateMetadataValueInputType, required: true, camelize: false
    argument :authenticity_token, String, required: false
  end
end
