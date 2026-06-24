module Types
  # Federation mesh type `mutation_KickoffWGSWorkflow_items_inputs` (CZID-304).
  class KickoffWgsWorkflowItemInputsType < Types::BaseObject
    graphql_name "mutation_KickoffWGSWorkflow_items_inputs"

    field :accession_id, Types::JsonScalar, null: true, camelize: false
    field :accession_name, Types::JsonScalar, null: true, camelize: false
    field :taxon_id, Types::JsonScalar, null: true, camelize: false
    field :taxon_name, Types::JsonScalar, null: true, camelize: false
    field :technology, String, null: true, camelize: false
    field :card_version, String, null: true, camelize: false
    field :wildcard_version, String, null: true, camelize: false
  end
end
