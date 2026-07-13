module Types
  # The discovery filter bag for fedWorkflowRunsAggregate (CZID-285), forwarded to the
  # projects discovery scope. camelCase on the wire, snake readers for the resolver.
  class FedWorkflowRunsAggregateTodoRemoveInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_todoRemove_Input"

    argument :project_id, String, required: false
    argument :domain, String, required: false
    argument :host, [Int], required: false
    argument :location_v2, [String], required: false
    argument :taxon_thresholds, [Types::FedWorkflowRunsAggregateTodoRemoveTaxonThresholdInputType], required: false
    argument :annotations, [Types::FedWorkflowRunsAggregateTodoRemoveAnnotationInputType], required: false
    argument :tissue, [String], required: false
    argument :visibility, String, required: false
    argument :time, [String], required: false
    argument :taxa_levels, [String], required: false
    argument :taxon, [Int], required: false
    argument :search, String, required: false
  end
end
