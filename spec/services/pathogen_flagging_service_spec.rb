require "rails_helper"

RSpec.describe PathogenFlaggingService, type: :service do
  # Known pathogen tax ids: 573 (Klebsiella pneumoniae), 1313 (Streptococcus pneumoniae)
  # Non-pathogen: 570 (Klebsiella genus)
  let(:pathogen_tax_ids) { [573, 1313] }

  before do
    # Global pathogen list -> version -> pathogens
    global_list = create(:pathogen_list, creator_id: nil, is_global: true)
    list_version = create(:pathogen_list_version, version: "0.1.0", pathogen_list_id: global_list.id)
    create(:taxon_lineage, tax_name: "Klebsiella pneumoniae", taxid: 573, species_name: "Klebsiella pneumoniae", superkingdom_taxid: 2, superkingdom_name: "Bacteria")
    create(:taxon_lineage, tax_name: "Streptococcus pneumoniae", taxid: 1313, species_name: "Streptococcus pneumoniae", superkingdom_taxid: 2, superkingdom_name: "Bacteria")
    pathogen_tax_ids.each do |tax_id|
      list_version.pathogens << create(:pathogen, tax_id: tax_id)
    end

    project = create(:project)
    @pipeline_run = create(:pipeline_run, sample: create(:sample, project: project))
    @other_pipeline_run = create(:pipeline_run, sample: create(:sample, project: project))

    # taxon counts: pathogen 573 + non-pathogen 570 for @pipeline_run
    create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 573, count: 100)
    create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 570, count: 100)
    # pathogen 1313 for @other_pipeline_run
    create(:taxon_count, pipeline_run: @other_pipeline_run, tax_id: 1313, count: 100)
  end

  describe "#call" do
    it "returns only known-pathogen tax_ids grouped by pipeline_run_id" do
      result = PathogenFlaggingService.call(
        pipeline_run_ids: [@pipeline_run.id, @other_pipeline_run.id],
        background_id: nil
      )

      expect(result[@pipeline_run.id]).to contain_exactly(573)
      expect(result[@other_pipeline_run.id]).to contain_exactly(1313)
    end

    it "excludes non-pathogen tax_ids from the result" do
      result = PathogenFlaggingService.call(
        pipeline_run_ids: [@pipeline_run.id],
        background_id: nil
      )

      expect(result[@pipeline_run.id]).not_to include(570)
    end

    it "omits pipeline runs that have no known pathogens" do
      no_pathogen_run = create(:pipeline_run, sample: create(:sample, project: create(:project)))
      create(:taxon_count, pipeline_run: no_pathogen_run, tax_id: 570, count: 100)

      result = PathogenFlaggingService.call(
        pipeline_run_ids: [no_pathogen_run.id],
        background_id: nil
      )

      expect(result).not_to have_key(no_pathogen_run.id)
    end

    it "returns an empty hash when no pipeline run ids are provided" do
      result = PathogenFlaggingService.call(pipeline_run_ids: [], background_id: nil)
      expect(result).to eq({})
    end

    context "when a background_id is provided" do
      it "validates the background exists during initialization" do
        expect do
          PathogenFlaggingService.call(pipeline_run_ids: [@pipeline_run.id], background_id: -1)
        end.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "does not raise when the background exists" do
        background = create(:background, name: "test background")
        expect do
          PathogenFlaggingService.call(pipeline_run_ids: [@pipeline_run.id], background_id: background.id)
        end.not_to raise_error
      end
    end
  end
end
