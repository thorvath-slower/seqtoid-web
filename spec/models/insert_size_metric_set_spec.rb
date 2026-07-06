require 'rails_helper'

RSpec.describe InsertSizeMetricSet, type: :model do
  let(:pipeline_run) { create(:pipeline_run, sample: create(:sample, project: create(:project))) }

  context "associations" do
    it "belongs to a pipeline_run" do
      metric_set = create(:insert_size_metric_set, pipeline_run: pipeline_run)
      expect(metric_set.pipeline_run).to eq(pipeline_run)
    end

    it "is invalid without a pipeline_run" do
      metric_set = build(:insert_size_metric_set, pipeline_run: nil)
      expect(metric_set).not_to be_valid
      expect(metric_set.errors[:pipeline_run]).to be_present
    end
  end

  context "validations" do
    it "is valid with all required attributes" do
      expect(build(:insert_size_metric_set, pipeline_run: pipeline_run)).to be_valid
    end

    # These columns are integer-typed, so a decimal is truncated on assignment
    # before validation runs; only presence is meaningfully assertable here.
    %i[median mode median_absolute_deviation min max read_pairs].each do |field|
      it "requires a #{field}" do
        metric_set = build(:insert_size_metric_set, pipeline_run: pipeline_run, field => nil)
        expect(metric_set).not_to be_valid
        expect(metric_set.errors[field]).to be_present
      end
    end

    %i[mean standard_deviation].each do |field|
      it "requires a numeric #{field}" do
        metric_set = build(:insert_size_metric_set, pipeline_run: pipeline_run, field => nil)
        expect(metric_set).not_to be_valid
        expect(metric_set.errors[field]).to be_present
      end

      it "allows a decimal #{field}" do
        metric_set = build(:insert_size_metric_set, pipeline_run: pipeline_run, field => 3.14)
        expect(metric_set).to be_valid
      end
    end
  end
end
