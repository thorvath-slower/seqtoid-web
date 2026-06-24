module Types
  # Federation mesh type `mutation_KickoffWGSWorkflow_items` (CZID-304): one of the
  # sample's workflow runs after a kickoff, from Sample#workflow_runs_info (wr.as_json
  # with input_error/inputs/parsed_cached_results + run_finalized). `id` is stringified.
  class KickoffWgsWorkflowItemType < Types::BaseObject
    graphql_name "mutation_KickoffWGSWorkflow_items"

    field :id, String, null: true, camelize: false
    field :status, String, null: true, camelize: false
    field :workflow, String, null: true, camelize: false
    field :wdl_version, String, null: true, camelize: false
    field :executed_at, String, null: true, camelize: false
    field :deprecated, Boolean, null: true, camelize: false
    field :input_error, Types::JsonScalar, null: true, camelize: false
    field :inputs, Types::KickoffWgsWorkflowItemInputsType, null: true, camelize: false
    field :parsed_cached_results, Types::KickoffWgsWorkflowItemParsedCachedResultsType, null: true, camelize: false
    field :run_finalized, Boolean, null: true, camelize: false
  end
end
