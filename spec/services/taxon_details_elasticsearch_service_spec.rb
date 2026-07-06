require 'rails_helper'

RSpec.describe TaxonDetailsElasticsearchService, type: :service do
  let(:pr_id_to_sample_id) { { 10 => 100, 11 => 101 } }
  let(:samples) { [double("sample")] }
  let(:taxon_ids) { [570, 573] }

  let(:raw_metrics) { [{ "pr_id" => 10 }] }
  let(:results_by_pr) { { 10 => {} } }
  let(:final_dict) { { "taxon_details" => "value" } }

  before do
    allow(ElasticsearchQueryHelper).to receive(:all_metrics_per_sample_and_taxa).and_return(raw_metrics)
    allow(ElasticsearchQueryHelper).to receive(:organize_data_by_pr).and_return(results_by_pr)
    allow(ElasticsearchQueryHelper).to receive(:samples_taxons_details).and_return(final_dict)
  end

  describe "#call" do
    context "when a background_id is provided" do
      subject do
        TaxonDetailsElasticsearchService.call(
          pr_id_to_sample_id: pr_id_to_sample_id,
          samples: samples,
          taxon_ids: taxon_ids,
          background_id: 26
        )
      end

      it "queries metrics with the pr ids, taxon ids and the given background" do
        subject
        expect(ElasticsearchQueryHelper).to have_received(:all_metrics_per_sample_and_taxa)
          .with(pr_id_to_sample_id.keys, taxon_ids, 26)
      end

      it "does not remove the zscore (should_remove_zscore is false)" do
        subject
        expect(ElasticsearchQueryHelper).to have_received(:samples_taxons_details)
          .with(results_by_pr, samples, false)
      end

      it "returns the assembled dict" do
        expect(subject).to eq(final_dict)
      end
    end

    context "when background_id is nil" do
      subject do
        TaxonDetailsElasticsearchService.call(
          pr_id_to_sample_id: pr_id_to_sample_id,
          samples: samples,
          taxon_ids: taxon_ids,
          background_id: nil
        )
      end

      it "falls back to the default background" do
        default_bg = Rails.configuration.x.constants.default_background
        subject
        expect(ElasticsearchQueryHelper).to have_received(:all_metrics_per_sample_and_taxa)
          .with(pr_id_to_sample_id.keys, taxon_ids, default_bg)
      end

      it "removes the zscore (should_remove_zscore is true)" do
        subject
        expect(ElasticsearchQueryHelper).to have_received(:samples_taxons_details)
          .with(results_by_pr, samples, true)
      end
    end
  end
end
