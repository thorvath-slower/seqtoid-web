class IdseqContext < GraphQL::Query::Context
  def current_user
    self[:current_user]
  end

  # Mirror current_user: expose the request-scoped Power that GraphqlController seeds into
  # the context (context[:current_power] = Power.new(current_user)) so authorization hooks
  # and resolvers can read context.current_power the same way they read context.current_user.
  # Without this, IdseqContext has no current_power method and context.current_power raises
  # NoMethodError (#531).
  def current_power
    self[:current_power]
  end
end
