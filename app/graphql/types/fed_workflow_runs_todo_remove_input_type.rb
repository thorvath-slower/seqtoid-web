module Types
  # The discovery filter bag passed through to /workflow_runs.json. Field names mirror
  # the federation `todoRemove` input (camelCase on the wire, snake readers for the
  # resolver). CZID-285.
  class FedWorkflowRunsTodoRemoveInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRuns_input_todoRemove_Input"

    argument :domain, String, required: false
    argument :project_id, String, required: false
    argument :search, String, required: false
    argument :host, [Int], required: false
    argument :location_v2, [String], required: false
    argument :taxon, [Int], required: false
    argument :taxon_levels, [String], required: false
    argument :time, [String], required: false
    argument :tissue, [String], required: false
    argument :visibility, String, required: false
    argument :workflow, String, required: false
    argument :order_by, String, required: false
    argument :order_dir, String, required: false
    argument :authenticity_token, String, required: false
  end
end
