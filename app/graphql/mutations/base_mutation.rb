require 'graphql_auth_helpers'

module Mutations
  class BaseMutation < GraphQL::Schema::Mutation
    extend GraphqlAuthHelpers

    null false
    argument_class Types::BaseArgument
    field_class Types::BaseField

    private

    # Mutations, like QueryType, are not controllers and so do NOT auto-include Rails
    # helpers. Expose the request's user/power from the GraphQL context (GraphqlController
    # seeds them) so ported resolvers and the helpers they call resolve the bare
    # current_user/current_power the way they did under the controller — e.g.
    # BulkDownloadsHelper#validate_num_objects does `current_user.admin?` (#451). Mirrors
    # QueryType#current_user/#current_power (CZID-307 parity).
    def current_user
      context[:current_user]
    end

    def current_power
      context[:current_power]
    end
  end
end
