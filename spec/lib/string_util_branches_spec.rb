# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for StringUtil.humanize_step_name. The existing
# spec covers the nil-stage path and the custom-name HIT. These target the
# else/miss arms: a stage that has step_names but whose dag_name is NOT in the
# custom_step_names map (falls through to regex), and a stage that has no
# custom step_names at all (the outer guard false branch).
RSpec.describe StringUtil do
  describe "#humanize_step_name branch coverage" do
    it "falls through to the regex when the dag_name is not a custom step name (inner key? false)" do
      # HOST_FILTERING has a step_names map, but "RunValidateInput" maps to the
      # dag name "validate_input_out", which is not in that map.
      result = StringUtil.humanize_step_name(
        "RunValidateInput",
        PipelineRunStage::HOST_FILTERING_STAGE_NAME
      )
      expect(result).to eq("Validate Input")
    end

    it "uses the regex when the stage has no custom step_names (outer guard false)" do
      # ALIGNMENT stage has no "step_names" entry, so
      # stage_contains_custom_step_names is falsey and we skip straight to regex.
      result = StringUtil.humanize_step_name(
        "combine_taxon_counts_out",
        PipelineRunStage::ALIGNMENT_STAGE_NAME
      )
      expect(result).to eq("Combine Taxon Counts")
    end

    it "still humanizes a bare step name when no stage is given (nil-stage path)" do
      expect(StringUtil.humanize_step_name("subsampled_out")).to eq("Subsampled")
    end
  end

  describe "#integer?" do
    it "is true for integer-looking strings and false otherwise" do
      expect(StringUtil.integer?("42")).to be true
      expect(StringUtil.integer?("4.2")).to be false
      expect(StringUtil.integer?("abc")).to be false
    end
  end
end
