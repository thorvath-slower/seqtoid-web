module Queries
  # Ported from the GraphQL federation server (resolver-functions/MetadataFields) as
  # part of CZID-285. Mirrors SamplesController#metadata_fields (both paths return
  # MetadataField#field_info hashes). snapshotLinkId is accepted for query parity but
  # unused -- the federation resolver also posted to the non-snapshot /samples/metadata_fields.
  module MetadataFieldsQuery
    extend ActiveSupport::Concern

    included do
      field :MetadataFields,
            [Types::MetadataFieldType],
            null: true,
            camelize: false,
            resolver_method: :resolve_metadata_fields do
        argument :snapshot_link_id, String, required: false
        argument :input, Types::MetadataFieldsInputType, required: false
      end
    end

    def resolve_metadata_fields(input:, snapshot_link_id: nil)
      current_power = context[:current_power]
      sample_ids = (input&.sample_ids || []).map(&:to_i)

      if sample_ids.length == 1
        sample = current_power.viewable_samples.find(sample_ids[0])
        sample.metadata_fields_info
      else
        samples = current_power.viewable_samples.where(id: sample_ids)
        MetadataField.by_samples(samples)
      end
    end
  end
end
