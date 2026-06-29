require "rails_helper"

# CZID-158 — GraphQL schema contract.
#
# After the GraphQL federation collapse, the Rails-native `IdseqSchema` is THE contract with the
# frontend (the React/Relay client + the committed SDL/JSON in graphql_schema/). This test locks
# that surface: if the live schema drifts from the committed SDL, CI fails — forcing the change to
# be intentional and the snapshot to be regenerated + reviewed (so a field rename/removal can't
# silently break the client).
#
# The committed SDL is produced by lib/tasks/graphql.rake (GraphQL::RakeTask, schema IdseqSchema),
# which writes graphql_schema/czid_rails_schema.graphql via `IdseqSchema.to_definition` — the same
# method compared here, so the strings match exactly when in sync.
RSpec.describe "GraphQL schema contract" do
  it "the live IdseqSchema matches the committed SDL (graphql_schema/czid_rails_schema.graphql)" do
    committed_sdl = Rails.root.join("graphql_schema", "czid_rails_schema.graphql").read
    live_sdl = IdseqSchema.to_definition

    expect(live_sdl).to eq(committed_sdl), <<~MSG
      The GraphQL schema has drifted from the committed SDL
      (graphql_schema/czid_rails_schema.graphql). This SDL is the contract with the frontend
      (Rails-native /graphql, post federation-collapse). If the change is intentional, regenerate
      the committed schema and commit it:

        bundle exec rake graphql:schema:dump

      (refreshes both czid_rails_schema.graphql and .json). If it is NOT intentional, you removed
      or renamed part of the API the client depends on — revert it.
    MSG
  end
end
