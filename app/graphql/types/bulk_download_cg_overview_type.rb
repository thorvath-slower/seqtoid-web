module Types
  # Ported from the GraphQL federation server (CZID-285). cgOverviewRows is a
  # list-of-lists-of-strings (the CSV preview rows); all-nullable to match the
  # federation type [[String]].
  class BulkDownloadCgOverviewType < Types::BaseObject
    graphql_name "BulkDownloadCGOverview"

    field :cgOverviewRows, [[String, { null: true }], { null: true }], null: true, camelize: false
  end
end
