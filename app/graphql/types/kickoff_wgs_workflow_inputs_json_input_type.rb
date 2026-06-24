module Types
  # Federation mesh input `mutationInput_KickoffWGSWorkflow_input_inputs_json_Input`
  # (CZID-304): the workflow run inputs, serialized to inputs_json for
  # create_and_dispatch_workflow_run.
  class KickoffWgsWorkflowInputsJsonInputType < Types::BaseInputObject
    graphql_name "mutationInput_KickoffWGSWorkflow_input_inputs_json_Input"

    argument :accession_id, String, required: false, camelize: false
    argument :accession_name, String, required: false, camelize: false
    argument :taxon_id, String, required: false, camelize: false
    argument :taxon_name, String, required: false, camelize: false
    argument :alignment_config_name, String, required: false, camelize: false
    argument :technology, String, required: false, camelize: false
  end
end
