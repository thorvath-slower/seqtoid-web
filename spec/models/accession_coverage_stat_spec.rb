require 'rails_helper'

RSpec.describe AccessionCoverageStat, type: :model do
  context "associations" do
    it "belongs to a pipeline_run" do
      pipeline_run = create(:pipeline_run, sample: create(:sample, project: create(:project)))
      stat = create(:accession_coverage_stat, pipeline_run: pipeline_run)
      expect(stat.pipeline_run).to eq(pipeline_run)
    end

    it "is invalid without a pipeline_run" do
      stat = build(:accession_coverage_stat, pipeline_run: nil)
      expect(stat).not_to be_valid
      expect(stat.errors[:pipeline_run]).to be_present
    end
  end

  context "validations" do
    let(:pipeline_run) { create(:pipeline_run, sample: create(:sample, project: create(:project))) }

    it "is valid with all required attributes" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run)
      expect(stat).to be_valid
    end

    it "requires accession_id" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, accession_id: nil)
      expect(stat).not_to be_valid
      expect(stat.errors[:accession_id]).to include("can't be blank")
    end

    it "requires accession_name" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, accession_name: nil)
      expect(stat).not_to be_valid
      expect(stat.errors[:accession_name]).to include("can't be blank")
    end

    it "requires taxid" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, taxid: nil)
      expect(stat).not_to be_valid
      expect(stat.errors[:taxid]).to include("can't be blank")
    end

    it "rejects a negative num_contigs" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, num_contigs: -1)
      expect(stat).not_to be_valid
      expect(stat.errors[:num_contigs]).to be_present
    end

    it "rejects a negative num_reads" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, num_reads: -1)
      expect(stat).not_to be_valid
      expect(stat.errors[:num_reads]).to be_present
    end

    it "rejects a negative score" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, score: -1)
      expect(stat).not_to be_valid
      expect(stat.errors[:score]).to be_present
    end

    it "rejects a negative coverage_breadth" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, coverage_breadth: -0.5)
      expect(stat).not_to be_valid
      expect(stat.errors[:coverage_breadth]).to be_present
    end

    it "rejects a negative coverage_depth" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run, coverage_depth: -0.5)
      expect(stat).not_to be_valid
      expect(stat.errors[:coverage_depth]).to be_present
    end

    it "allows zero for the numeric coverage fields" do
      stat = build(:accession_coverage_stat, pipeline_run: pipeline_run,
                                             num_contigs: 0, num_reads: 0, score: 0,
                                             coverage_breadth: 0, coverage_depth: 0)
      expect(stat).to be_valid
    end
  end
end
