# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for DeletionValidationService. Targets the
# opposite arms the main spec leaves untaken: non-integer query_ids (the
# ArrayUtil.all_integers? else), an unknown workflow (WorkflowNotFoundError ->
# error path -> result[:error] else), and the long-read/nanopore technology
# branch.
RSpec.describe DeletionValidationService, type: :service do
  create_users

  describe "query_ids normalization" do
    it "keeps query_ids as-is when they are not all integers (the else branch)" do
      # Mixed / non-integer ids -> the else keeps them untouched. With CG
      # workflow the string ids simply match nothing and come back invalid.
      response = DeletionValidationService.call(
        query_ids: %w[abc def],
        user: @joe,
        workflow: WorkflowRun::WORKFLOW[:consensus_genome]
      )
      expect(response[:valid_ids]).to be_empty
      expect(response[:invalid_sample_ids]).to be_an(Array)
    end
  end

  describe "unknown workflow" do
    it "captures the error and returns it in the result (the error-present else)" do
      expect(LogUtil).to receive(:log_error).with(
        a_string_matching(/DeletionValidationEvent/), hash_including(:exception)
      )

      response = DeletionValidationService.call(
        query_ids: [1, 2, 3],
        user: @joe,
        workflow: "not-a-real-workflow"
      )

      expect(response[:error]).to eq(DeletionValidationService::DELETION_VALIDATION_ERROR)
      expect(response[:valid_ids]).to be_empty
      expect(response[:invalid_sample_ids]).to be_empty
    end
  end

  describe "long-read (nanopore) technology branch" do
    before do
      @project = create(:project, users: [@joe])
      nanopore = PipelineRun::TECHNOLOGY_INPUT[:nanopore]
      @lr_sample = create(:sample, project: @project, user: @joe,
                                   name: "long read sample",
                                   pipeline_runs_data: [{ finalized: 1, technology: nanopore }])
    end

    it "validates long-read mNGS samples using the nanopore technology (the else)" do
      response = DeletionValidationService.call(
        query_ids: [@lr_sample.id],
        user: @joe,
        workflow: WorkflowRun::WORKFLOW[:long_read_mngs]
      )

      expect(response[:error]).to be_nil
      expect(response[:valid_ids]).to include(@lr_sample.id)
    end
  end
end
