module Types
  # Federation mesh type `SampleMetadata` (CZID-285): the root payload of the
  # SampleMetadata query -- the data behind the sample details metadata sidebar.
  # The top-level collection* scalars exist in the federation contract but are not
  # populated by SamplesController#metadata (the REST payload only carries `metadata`
  # and `additional_info`), so they resolve to nil -- matching the federation output.
  class SampleMetadataType < Types::BaseObject
    graphql_name "SampleMetadata"

    field :collectionDate, String, null: true, camelize: false
    field :collectionLocationV2, String, null: true, camelize: false
    field :nucleotideType, String, null: true, camelize: false
    field :sampleType, String, null: true, camelize: false
    field :waterControl, String, null: true, camelize: false
    field :metadata, [Types::SampleMetadataMetadataItemType], null: true, camelize: false
    field :additional_info, Types::SampleMetadataAdditionalInfoType, null: true, camelize: false
  end
end
