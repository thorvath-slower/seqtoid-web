module Types
  # Federation mesh union
  # `query_SampleMetadata_metadata_items_location_validated_value` (CZID-285).
  # The resolver tags each value with `__typename` (mirroring the federation
  # post-processing) so resolve_type can pick the member type without re-deriving it.
  class SampleMetadataLocationValidatedValueUnion < Types::BaseUnion
    graphql_name "query_SampleMetadata_metadata_items_location_validated_value"

    possible_types Types::SampleMetadataLocationOneof0Type,
                   Types::SampleMetadataLocationOneof1Type

    def self.resolve_type(object, _context)
      if object[:__typename] == Types::SampleMetadataLocationOneof1Type.graphql_name
        Types::SampleMetadataLocationOneof1Type
      else
        Types::SampleMetadataLocationOneof0Type
      end
    end
  end
end
