module Queries
  # Ported from the GraphQL federation server (resolver-functions/ValidateUserCanDeleteObjects)
  # as part of CZID-285. Mirrors SamplesController#validate_user_can_delete_objects, and
  # synthesizes validIdsStrings the way the federation resolver did.
  module ValidateUserCanDeleteObjectsQuery
    extend ActiveSupport::Concern

    included do
      field :ValidateUserCanDeleteObjects,
            Types::ValidateUserCanDeleteObjectsType,
            null: false,
            camelize: false,
            resolver_method: :resolve_validate_user_can_delete_objects do
        argument :input, Types::ValidateUserCanDeleteObjectsInputType, required: true
      end
    end

    def resolve_validate_user_can_delete_objects(input:)
      current_user = context[:current_user]
      current_power = context[:current_power]
      selected_ids = input.selected_ids_strings || input.selected_ids

      validated_objects = DeletionValidationService.call(
        query_ids: selected_ids,
        user: current_user,
        workflow: input.workflow
      )
      valid_ids = validated_objects[:valid_ids]
      invalid_sample_ids = validated_objects[:invalid_sample_ids]
      error = validated_objects[:error]

      invalid_sample_names = []
      if error.nil? && !invalid_sample_ids.empty?
        invalid_sample_names = current_power.samples.where(id: invalid_sample_ids).pluck(:name)
      end

      {
        valid_ids: valid_ids,
        valid_ids_strings: (valid_ids || []).map(&:to_s),
        invalid_sample_names: invalid_sample_names,
        error: error,
      }
    end
  end
end
