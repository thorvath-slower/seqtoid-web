module Types
  # `todoRemove.taxonThresholds` item for fedWorkflowRunsAggregate (CZID-285).
  class FedWorkflowRunsAggregateTodoRemoveTaxonThresholdInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_todoRemove_taxonThresholds_items_Input"

    argument :metric, String, required: false, camelize: false
    argument :count_type, String, required: false, camelize: false
    argument :operator, String, required: false, camelize: false
    argument :value, String, required: false, camelize: false
  end
end
