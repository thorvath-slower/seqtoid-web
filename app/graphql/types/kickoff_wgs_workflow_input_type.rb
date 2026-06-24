module Types
  # Federation mesh input `mutationInput_KickoffWGSWorkflow_input_Input` (CZID-304).
  class KickoffWgsWorkflowInputType < Types::BaseInputObject
    graphql_name "mutationInput_KickoffWGSWorkflow_input_Input"

    argument :inputs_json, Types::KickoffWgsWorkflowInputsJsonInputType, required: false, camelize: false
    argument :workflow, String, required: false, camelize: false
    argument :authenticity_token, String, required: false
  end
end
