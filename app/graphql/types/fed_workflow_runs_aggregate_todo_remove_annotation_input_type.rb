module Types
  # `todoRemove.annotations` item for fedWorkflowRunsAggregate (CZID-285).
  class FedWorkflowRunsAggregateTodoRemoveAnnotationInputType < Types::BaseInputObject
    graphql_name "queryInput_fedWorkflowRunsAggregate_input_todoRemove_annotations_items_Input"

    argument :name, String, required: false, camelize: false
  end
end
