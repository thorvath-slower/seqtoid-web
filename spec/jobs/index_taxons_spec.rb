require "rails_helper"

RSpec.describe IndexTaxons, type: :job do
  describe "#perform" do
    let(:background_id) { 42 }
    let(:pipeline_run_id) { 99 }

    it "calls the taxon indexing lambda with the background id and the pipeline run in an array" do
      expect(ElasticsearchQueryHelper).to receive(:call_taxon_indexing_lambda).with(background_id, [pipeline_run_id])
      IndexTaxons.perform(background_id, pipeline_run_id)
    end

    it "propagates errors raised by the indexing helper" do
      allow(ElasticsearchQueryHelper).to receive(:call_taxon_indexing_lambda).and_raise(StandardError.new("lambda down"))
      expect do
        IndexTaxons.perform(background_id, pipeline_run_id)
      end.to raise_error(StandardError, "lambda down")
    end
  end
end
