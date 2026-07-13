module Types
  # Ported from the GraphQL federation server (CZID-285). Mirrors the shape the
  # federation's CZIDREST `ZipLink` operation returned to Relay.
  class ZipLinkType < Types::BaseObject
    graphql_name "ZipLink"

    field :url, String, null: true
    field :error, String, null: true
  end
end
